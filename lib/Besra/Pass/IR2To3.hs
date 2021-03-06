
module Besra.Pass.IR2To3 ( pass ) where

import Protolude hiding ( pass )
import Unsafe ( unsafeFromJust )
import Data.Bitraversable ( bitraverse )
import qualified Data.Map as Map
import qualified Data.List as List
import qualified Besra.Types.IR2 as IR2
import qualified Besra.Types.IR3 as IR3
import Besra.TypeSystem.Subst
import Besra.Types.IR3 ( Qual(..) )
import Besra.Types.CompilerState
import Besra.Types.Ann
import Besra.Types.Id
import Data.Graph ( SCC(..), stronglyConnComp )


{-
This pass adds more information to the AST of expressions/declarations
to prepare for typechecking:

1. Adds the scheme to each constructor in an expression.
2. Adds the scheme to each constructor in a pattern match.
3. Groups all bindings/type annotations on top level and in let expressions
   together and orders them according to what the typechecker expects.
4. Adds type annotations to all bindings in impls.
-}

type KI = KindInferred

-- | Mapping from constructor names to type schemes.
type SchemeMap = Map Id (IR3.Scheme KI)

data DesugarState = DesugarState { schemeMap :: SchemeMap, traits :: Map Id (IR2.Trait KI) }

type PassM = Reader DesugarState

pass :: CompilerState2 KI -> IR2.Module KI -> (IR3.Module KI, CompilerState3 KI)
pass (CompilerState2 adts traits impls kEnv) m =
  let conInfo = prepareConInfo adts
      passState = DesugarState conInfo (mkTraitMap traits)
      mkTraitMap = Map.fromList . map toTraitTuple
      toTraitTuple t@(IR2.Trait _ _ (IR2.IsIn _ name _) _) = (name, t)
      m' = runReader (desugar m) passState
      traits' = map desugarTrait traits
      impls' = map (flip runReader passState . desugar) impls
   in (m', CompilerState3 adts traits' impls' kEnv)

prepareConInfo :: [IR2.ADT KI] -> SchemeMap
prepareConInfo =
  let f (IR2.ADT _ _ conDecls) = Map.fromList $ map extractScheme conDecls
      extractScheme (IR2.ConDecl ann name ty) = (name, toScheme ann ty)
   in foldMap f

toScheme :: Ann KI -> IR2.Type KI -> IR3.Scheme KI
toScheme ann ty = IR3.ForAll ann [] ([] :=> desugarType ty)

class Desugar a where
  type Result a

  desugar :: a -> PassM (Result a)

instance Desugar a => Desugar [a] where
  type Result [a] = [Result a]

  desugar = traverse desugar

instance Desugar (IR2.Module KI) where
  type Result (IR2.Module KI) = IR3.Module KI

  desugar (IR2.Module decls) = do
    -- Semantic analysis only allows explicit bindings on top level.
    (expls, _) <- toBG decls
    pure $ IR3.Module expls

instance Desugar (IR2.Expr KI) where
  type Result (IR2.Expr KI) = IR3.Expr KI

  desugar = \case
    IR2.ELit ann lit -> pure $ IR3.ELit ann lit
    IR2.EVar ann var -> pure $ IR3.EVar ann var
    IR2.ECon ann name -> do
      sch <- unsafeFromJust <$> asks (Map.lookup name . schemeMap)
      pure $ IR3.ECon ann name sch
    IR2.ELam ann pats body ->
      -- NOTE: this only applies to anonymous lambdas,
      -- named functions are already handled with toBG
      let alt = (,) <$> desugar pats <*> desugar body
       in IR3.ELam ann <$> alt
    IR2.EApp ann f arg ->
      IR3.EApp ann <$> desugar f <*> desugar arg
    IR2.EIf ann c t f ->
      IR3.EIf ann <$> desugar c <*> desugar t <*> desugar f
    IR2.ECase ann e clauses ->
      IR3.ECase ann <$> desugar e
                    <*> traverse (bitraverse desugar desugar) clauses
    IR2.ELet ann decls expr ->
      IR3.ELet ann <$> toBG decls <*> desugar expr

instance Desugar (IR2.Pattern KI) where
  type Result (IR2.Pattern KI) = IR3.Pattern KI

  desugar = \case
    IR2.PWildcard ann -> pure $ IR3.PWildcard ann
    IR2.PLit ann lit -> pure $ IR3.PLit ann lit
    IR2.PVar ann var -> pure $ IR3.PVar ann var
    IR2.PCon ann name pats -> do
      sch <- unsafeFromJust <$> asks (Map.lookup name . schemeMap)
      IR3.PCon ann name sch <$> desugar pats
    IR2.PAs ann name pat -> IR3.PAs ann name <$> desugar pat

instance Desugar (IR2.Impl KI) where
  type Result (IR2.Impl KI) = IR3.Impl KI

  desugar (IR2.Impl ann ps p@(IR2.IsIn _ traitName _) bs) = do
    -- TODO maybe -> signal error
    (IR2.Trait _ _ traitPred typeAnns) <- asks (unsafeFromJust . Map.lookup traitName . traits)
    let subst = mkSubstForImpl traitPred p
        decls = map IR2.TypeAnnDecl typeAnns <> map IR2.BindingDecl bs
        ps' = map desugarPred ps
        p' = desugarPred p
    (expls, _) <- toBG decls  -- TODO Only explicits are possible here => signal error
    pure $ IR3.Impl ann ps' p' (applyToScheme subst ps' expls)

mkSubstForImpl :: IR2.Pred KI -> IR2.Pred KI -> Subst
mkSubstForImpl (IR2.IsIn _ _ traitTypes) (IR2.IsIn _ _ implTypes) =
  let traitVars = mapMaybe getTyvar traitTypes
      implTypes' = map desugarType implTypes
   in Subst $ zip traitVars implTypes'
  where
    getTyvar = \case
      IR2.TVar var -> Just var
      _ -> Nothing

applyToScheme :: Subst -> [IR3.Pred KI] -> [IR3.Explicit KI] -> [IR3.Explicit KI]
applyToScheme subst implPs = map f where
  f (IR3.Explicit name (IR3.ForAll ann ks (ps :=> ty)) alts) =
    let sch' = IR3.ForAll ann ks ((implPs <> ps) :=> ty)
     in IR3.Explicit name (apply subst sch') alts

desugarType :: IR2.Type ph -> IR3.Type ph
desugarType = \case
  IR2.TCon tycon -> IR3.TCon tycon
  IR2.TVar tyvar -> IR3.TVar tyvar
  IR2.TApp t1 t2 -> IR3.TApp (desugarType t1) (desugarType t2)

desugarPred :: IR2.Pred ph -> IR3.Pred ph
desugarPred (IR2.IsIn ann name tys) =
  IR3.IsIn ann name $ map desugarType tys

desugarTrait :: IR2.Trait ph -> IR3.Trait ph
desugarTrait (IR2.Trait ann ps p ts) =
  let ps' = map desugarPred ps
      p' = desugarPred p
      ts' = Map.fromList $ map desugarTypeAnn ts
   in IR3.Trait ann ps' p' ts'

desugarTypeAnn :: IR2.TypeAnn ph -> (Id, IR3.Scheme ph)
desugarTypeAnn (IR2.TypeAnn _ name (IR2.Scheme ann ps ty)) =
  (name, IR3.ForAll ann [] (map desugarPred ps :=> desugarType ty))

toBG :: [IR2.Decl KI] -> PassM (IR3.BindGroup KI)
toBG decls = do
  let groupedDecls = groupDecls decls
      (expDecls, impDecls) = List.partition hasTypeAnn groupedDecls
      hasTypeAnn (_, (ta, _)) = isJust ta
  exps <- traverse toExplicit expDecls
  imps <- toImplicits impDecls
  pure (exps, imps)

groupDecls :: [IR2.Decl KI] -> [(Id, (Maybe (IR2.Scheme KI), [IR2.Binding KI]))]
groupDecls decls = Map.toList $ foldr' f Map.empty decls
  where
    f = \case
      IR2.TypeAnnDecl ta -> Map.alter (addScheme ta) (typeAnnName ta)
      IR2.BindingDecl b -> Map.alter (addBinding b) (bindingName b)
    addBinding b = \case
      Nothing -> Just (Nothing, [b])
      Just (ta, bs) -> Just (ta, b:bs)
    addScheme (IR2.TypeAnn _ _ sch) = \case
      Nothing -> Just (Just sch, [])
      Just (_, bs) -> Just (Just sch, bs)

toExplicit :: (Id, (Maybe (IR2.Scheme KI), [IR2.Binding KI]))
           -> PassM (IR3.Explicit KI)
toExplicit (name, (Just (IR2.Scheme ann ps ty), bs)) = do
  bs' <- traverse convertBinding bs
  let ps' = map desugarPred ps
      ty' = desugarType ty
  pure $ IR3.Explicit name (IR3.ForAll ann [] (ps' :=> ty')) bs'
toExplicit (Id name, (Nothing, _)) =
  panic $ "Error in 'toExplicit' in IR2->3 pass for id = " <> name

convertBinding :: IR2.Binding KI -> PassM (IR3.Alt KI)
convertBinding (IR2.Binding _ _ e) = case e of
  IR2.ELam _ pats body -> (,) <$> desugar pats <*> desugar body
  _ -> ([], ) <$> desugar e

toImplicits :: [(Id, (Maybe (IR2.Scheme KI), [IR2.Binding KI]))]
            -> PassM [[IR3.Implicit KI]]
toImplicits decls = sortDecls <$> traverse f decls where
  sortDecls = map g . stronglyConnComp
  toImplicit name bs = IR3.Implicit name <$> traverse convertBinding bs
  names = map fst decls
  f (name, (_, bs)) = do
    implicit <- toImplicit name bs
    let referredNames = foldMap refersTo bs
    pure (implicit, name, names `List.intersect` referredNames)
  g = \case
    AcyclicSCC node -> [node]
    CyclicSCC nodes -> nodes


class RefersTo a where
  refersTo :: a -> [Id]

instance RefersTo a => RefersTo [a] where
  refersTo = foldMap refersTo

instance RefersTo b => RefersTo (a, b) where
  refersTo (_, b) = refersTo b

instance RefersTo (IR2.Binding ph) where
  refersTo (IR2.Binding _ _ expr) = refersTo expr

instance RefersTo (IR2.Expr ph) where
  refersTo = \case
    IR2.ELit {} -> mempty
    IR2.ECon {} -> mempty
    IR2.EVar _ name -> [name]
    IR2.ELam _ _ body -> refersTo body
    IR2.EApp _ f arg -> refersTo f <> refersTo arg
    IR2.EIf _ c t f -> refersTo c <> refersTo t <> refersTo f
    IR2.ECase _ expr clauses -> refersTo expr <> refersTo clauses
    IR2.ELet _ decls body -> refersTo decls <> refersTo body

instance RefersTo (IR2.Decl ph) where
  refersTo = \case
    IR2.BindingDecl b -> refersTo b
    IR2.TypeAnnDecl _ -> mempty

bindingName :: IR2.Binding KI -> Id
bindingName (IR2.Binding _ name _) = name

typeAnnName :: IR2.TypeAnn KI -> Id
typeAnnName (IR2.TypeAnn _ name _) = name

