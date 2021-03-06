
{-# LANGUAGE NoOverloadedLists, QuasiQuotes #-}

module Test.Besra.Pass.InferKindsSpec
  ( module Test.Besra.Pass.InferKindsSpec
  ) where

import Protolude hiding ( Type, pass )
import Test.Hspec
import qualified Data.Map as Map
import qualified Besra.Pass.IR1To2 as IR1To2
import qualified Besra.Pass.InferKinds as IK
import Besra.Parser
import Besra.TypeSystem.KindSolver
import Besra.Types.CompilerState
import Besra.Types.IR2
import Besra.Types.Kind
import Besra.Types.Ann
import Besra.Types.Span
import Besra.Types.Id
import NeatInterpolation


type Ann' = Ann KindInferred
type AnnTy' = AnnTy KindInferred
type ADTHead' = ADTHead KindInferred
type ADTBody' = ADTBody KindInferred
type ADT' = ADT KindInferred
type Trait' = Trait KindInferred
type Impl' = Impl KindInferred
type Module' = Module KindInferred
type Binding' = Binding KindInferred
type Expr' = Expr KindInferred
type TypeAnn' = TypeAnn KindInferred
type Scheme' = Scheme KindInferred
type Pred' = Pred KindInferred
type Type' = Type KindInferred
type CompilerState2' = CompilerState2 KindInferred

runPass :: Text -> Either KindError (Module', CompilerState2')
runPass input =
  let
    parseResult = parseFile "balance_operators.test" input
    passResult = case parseResult of
      Left err -> panic $ formatError err
      Right result ->
        let (ast, IR1To2.PassState{..}) = IR1To2.pass result
            kindEnv = Map.fromList [(Id "->", arrowK)]
            kEnv = Env kindEnv Map.empty
            compState = CompilerState2 adts traits impls kEnv
         in runExcept $ IK.pass compState ast
  in
    passResult

sp :: Span
sp = Span 0 0

-- This causes some of the errors/results to have 0..0 spans.
arrowK :: IKind
arrowK = IKArr sp (IStar sp) (IKArr sp (IStar sp) (IStar sp))

class Testable a where
  (==>) :: Text -> a -> IO ()

infixr 0 ==>

instance Testable [(Id, Kind)] where
  input ==> adtHeads = do
    let result = runPass input
    case result of
      Left err -> panic $ show err
      Right (_, CompilerState2 adts _ _ _) ->
        getAdtKind <$> adts `shouldBe` adtHeads
    where getAdtKind (ADT _ (ADTHead name ty) _) = (name, getKind ty)
          getKind = \case
            TCon (Tycon (_, k) _) -> k
            TVar (Tyvar (_, k) _) -> k
            TApp t1 _ -> getKind t1

instance Testable [ADT KindInferred] where
  input ==> adts = do
    let result = runPass input
    case result of
      Left err -> panic $ show err
      Right (_, CompilerState2 adts' _ _ _) ->
        adts' `shouldBe` adts

instance Testable [Trait KindInferred] where
  input ==> traits = do
    let result = runPass input
    case result of
      Left err -> panic $ show err
      Right (_, CompilerState2 _ traits' _ _) ->
        traits' `shouldBe` traits

instance Testable [Impl KindInferred] where
  input ==> impls = do
    let result = runPass input
    case result of
      Left err -> panic $ show err
      Right (_, CompilerState2 _ _ impls' _) ->
        impls' `shouldBe` impls

instance Testable PredEnv where
  input ==> predKindEnv = do
    let result = runPass input
    case result of
      Left err -> panic $ show err
      Right (_, CompilerState2 _ _ _ (Env _ predKindEnv')) ->
        predKindEnv' `shouldBe` predKindEnv

instance Testable (Module KindInferred) where
  input ==> ast = do
    let result = runPass input
    case result of
      Left err -> panic $ show err
      Right (ast', CompilerState2 {}) ->
        ast' `shouldBe` ast

instance Testable TypeAnn' where
  input ==> t = input ==> Module [TypeAnnDecl t]

instance Testable Binding' where
  input ==> b = input ==> Module [BindingDecl b]

instance Testable KindError where
  input ==> err = do
    let result = runPass input
    case result of
      Left err' -> err' `shouldBe` err
      Right res -> panic $ show res

adt :: Ann' -> ADTHead' -> ADTBody' -> ADT'
adt = ADT

trait :: Span -> [Pred'] -> Pred' -> [TypeAnn'] -> Trait'
trait = Trait

binding :: Span -> Text -> Expr' -> Binding'
binding ann x = Binding ann (Id x)

typeAnn :: Span -> Id -> Scheme' -> TypeAnn'
typeAnn = TypeAnn

scheme :: Span -> [Pred KindInferred] -> Type' -> Scheme'
scheme = Scheme

arrow :: Span -> Type' -> Type' -> Type'
arrow ann t1 t2 =
  let k = KArr Star (KArr Star Star)
   in TApp (TApp (TCon (Tycon (ann, k) (Id "->"))) t1) t2

predEnv :: Text -> [IKind] -> PredEnv
predEnv predName = Map.singleton (Id predName)


-- Some test inputs would never get past SA phase,
-- but this is minimal needed for test.
spec :: Spec
spec = describe "kind inference algorithm" $ parallel $ do
  describe "ADT kind inference" $ parallel $ do
    it "can infer kinds for ADT with no type vars" $ do
      "data X = X" ==> [(Id "X", Star)]
      "data X = X Int" ==> [(Id "X", Star)]

    it "can infer kinds for ADT with type vars" $
      "data X a = X a" ==> [(Id "X", KArr Star Star)]

    it "can infer kinds for ADT with phantom type vars" $
      "data X a = X" ==> [(Id "X", KArr Star Star)]

    it "can infer kinds for ADTs with no body" $ do
      "data X" ==> [(Id "X", Star)]
      "data Y a" ==> [(Id "Y", KArr Star Star)]

    it "can infer kinds for ADT with multiple variants" $ do
      "data X = X | Y" ==> [(Id "X", Star)]
      "data X a = X a | Y a" ==> [(Id "X", KArr Star Star)]
      "data Maybe a = Just a | Nothing" ==> [(Id "Maybe", KArr Star Star)]
      "data Either a b = Left a | Right b"
        ==> [(Id "Either", KArr Star (KArr Star Star))]
      "data X f a = X (f a) | Y a"
        ==> [(Id "X", KArr (KArr Star Star) (KArr Star Star))]

    it "can infer kinds for 'Fix' data type" $
      "data Fix f = Fix (f (Fix f))"
        ==> [(Id "Fix", KArr (KArr Star Star) Star)]

    it "can infer kinds for ADT depending on another ADT" $ do
      [text|
        data X = X
        data Y = Y X
        |] ==> [(Id "X", Star), (Id "Y", Star)]
      [text|
        data X a = X
        data Y = Y (X Y)
        |] ==> [(Id "X", KArr Star Star), (Id "Y", Star)]

    it "can infer kinds for mutually referring ADTs" $ do
      [text|
        data A = Empty | A B
        data B = B A
        |] ==> [(Id "A", Star), (Id "B", Star)]
      [text|
        data A a = Empty | A B
        data B = B (A C)
        data C c = C
        |] ==> [ (Id "C", KArr Star Star)
               , (Id "A", KArr (KArr Star Star) Star)
               , (Id "B", Star) ]
      [text|
        data A a = Empty | A B
        data B = B (A C)
        data C a = C
        |] ==> [ (Id "C", KArr Star Star)
               , (Id "A", KArr (KArr Star Star) Star)
               , (Id "B", Star) ]

    it "enriches ADT with kind information" $ do
      let name = Id "Either"
          eitherCon = TCon $ Tycon (Span 5 11, KArr Star (KArr Star Star)) name
          aTy ann = TVar $ Tyvar (ann, Star) (Id "a")
          bTy ann = TVar $ Tyvar (ann, Star) (Id "b")
          eitherTy = TApp (TApp eitherCon (aTy (Span 12 13))) (bTy (Span 14 15))
          arrowTy ann a = TApp (TApp (TCon $ Tycon (ann,
                           KArr Star (KArr Star Star)) (Id "->")) a)
          leftTy = arrowTy (Span 18 24) (aTy (Span 23 24)) eitherTy
          rightTy = arrowTy (Span 27 34) (bTy (Span 33 34)) eitherTy
          conDecls = [ ConDecl (Span 18 24) (Id "Left") leftTy
                     , ConDecl (Span 27 34) (Id "Right") rightTy]
      "data Either a b = Left a | Right b"
        ==> [adt (Span 0 34) (ADTHead name eitherTy) conDecls]

    it "returns an error when kind unification failed" $ do
      "data X f a = X (f a) | Y f"
        ==> UnificationFail (IKArr (Span 16 19) (IKVar (Span 18 19) $ Id "k7")
                              (IStar sp)) (IStar sp)
      [text|
        data X a = X
        data Y = Y (X X)
        |] ==> UnificationFail (IStar (Span 7 8))
                (IKArr (Span 5 8) (IStar (Span 7 8)) (IStar (Span 5 8)))

    it "returns an error for trying to create an infinite kind" $ do
      "data X a = X (X X)"
        ==> InfiniteKind (Id "k5")
                         (IKArr (Span 5 8) (IKVar (Span 16 17) $ Id "k5") (IStar sp))
      "data X a = X (a X)"
        ==> InfiniteKind (Id "k9")
                         (IKArr (Span 14 17)
                          (IKArr (Span 5 8) (IKVar (Span 7 8) $ Id "k9")
                                    (IStar sp)) (IStar sp))

  describe "trait kind inference" $ parallel $ do
    it "can infer kinds for traits without type signatures" $ do
      "trait Eq a where" ==> predEnv "Eq" [IStar (Span 9 10)]
      "trait Convert a b where"
        ==> predEnv "Convert" [IStar (Span 14 15), IStar (Span 16 17)]
      "trait Monad m where" ==> predEnv "Monad" [IStar (Span 12 13)]
      [text|
        trait Eq a where
        trait Eq a => Ord a where
          |] ==> Map.fromList [ (Id "Eq", [IStar (Span 9 10)])
                              , (Id "Ord", [IStar (Span 9 10)])]

    it "can infer kinds for traits with single type signature" $ do
      [text|
        trait Eq a where
          (==) : a -> a -> Bool
        |] ==> predEnv "Eq" [IStar sp]
      [text|
        trait Functor f where
          map : (a -> b) -> (f a -> f b)
        |] ==> predEnv "Functor" [IKArr (Span 50 53) (IStar sp) (IStar sp)]

    it "can infer kinds for traits with multiple type signatures" $ do
      [text|
        trait MyClass a b where
          func1 : a -> a -> Bool
          func2 : b a -> a -> Bool
        |] ==> predEnv "MyClass" [IStar sp, IKArr (Span 59 62) (IStar sp) (IStar sp)]
      [text|
        data Fix f = Fix (f (Fix f))
        trait MyClass a b where
          func1 : a -> a -> Bool
          func2 : Fix b -> a -> Bool
        |] ==> predEnv "MyClass" [IStar sp, IKArr (Span 18 26) (IStar sp) (IStar sp)]

    it "can infer kinds for traits with supertraits" $ do
      let kF = IKArr (Span 89 92) (IStar sp) (IStar sp)
      [text|
        trait Functor f => Applicative f where
        trait Functor f where
          map : (a -> b) -> (f a -> f b)
        |] ==> Map.fromList [(Id "Functor", [kF]), (Id "Applicative", [kF])]

    it "can infer kinds for traits with types that require other traits" $ do
      let kF sp' = IKArr sp' (IStar sp) (IStar sp)
      [text|
        trait Applicative f where
          (<*>) : Functor f => f (a -> b) -> f a -> f b
        trait Functor f where
          map : (a -> b) -> (f a -> f b)
        |] ==> Map.fromList [ (Id "Functor", [kF (Span 124 127)])
                            , (Id "Applicative", [kF (Span 70 73)])]

    it "enriches trait with kind information" $ do
      let var ann x = TVar $ Tyvar ann (Id x)
          mkF ann = var (ann, KArr Star Star) "f"
          tyaX = TypeAnn (Span 24 33) (Id "x") schX
          tyaY = TypeAnn (Span 74 86) (Id "y") schY
          tyaY' = TypeAnn (Span 61 86) (Id "y") schY'
          schX = Scheme (Span 28 33) [] tyX
          schY = Scheme (Span 78 86) [] tyY
          schY' = Scheme (Span 65 86)
                  [IsIn (Span 65 74) (Id "MyClass") [mkF (Span 73 74)]] tyY
          tyX = TApp (TVar $ Tyvar (Span 28 29, KArr Star Star) (Id "f"))
                    (TCon $ Tycon (Span 30 33, Star) (Id "Int"))
          tyY = TApp (TVar $ Tyvar (Span 78 79, KArr Star Star) (Id "f"))
                    (TCon $ Tycon (Span 80 86, Star) (Id "String"))
      [text|
        trait MyClass f where
          x : f Int
        trait MyClass f => My2ndClass f where
          y : f String
        |] ==> [ trait (Span 0 33) []
                  (IsIn (Span 6 15) (Id "MyClass") [mkF (Span 14 15)]) [tyaX]
               , trait (Span 34 86)
                  [IsIn (Span 40 49) (Id "MyClass") [mkF (Span 48 49)]]
                  (IsIn (Span 53 65) (Id "My2ndClass") [mkF (Span 64 65)])
                  [tyaY]]
      [text|
        trait MyClass f where
          x : f Int
        trait My2ndClass f where
          y : MyClass f => f String
        |] ==> [ trait (Span 0 33) []
                  (IsIn (Span 6 15) (Id "MyClass") [mkF (Span 14 15)]) [tyaX]
               , trait (Span 34 86) []
                  (IsIn (Span 40 52) (Id "My2ndClass") [mkF (Span 51 52)])
                  [tyaY'] ]

    it "returns error during unification failure in trait head" $
      [text|
        trait X a where
          x : a Int
        trait X a => Y a where
          y : a
          |] ==> UnificationFail (IStar (Span 57 58))
                  (IKArr (Span 22 27) (IStar (Span 24 27)) (IStar (Span 22 27)))

    it "returns error during unification failure in trait body" $
      [text|
        trait X a where
          x : a
          y : a Int
          |] ==> UnificationFail (IStar (Span 22 23))
                  (IKArr (Span 30 35) (IKVar (Span 32 35) $ Id "k3")
                                      (IStar (Span 30 35)))

    it "returns error when trying to construct infinite kinds" $
      [text|
        trait MyClass a where
          x : a a
        |] ==> InfiniteKind (Id "k2")
                (IKArr (Span 28 31) (IKVar (Span 30 31) (Id "k2"))
                                    (IStar (Span 28 31)))

  describe "impl kind inference" $ parallel $ do
    let impl :: Ann' -> [Pred'] -> Pred' -> [Binding'] -> Impl'
        impl = Impl
    it "can infer kind for type annotations inside impl" $ do
      let tyInt = TCon (Tycon (Span 55 58, Star) (Id "Int"))
          x = binding (Span 67 103) "x" letExpr
          letExpr = ELet (Span 71 103) [taY] (ECon (Span 96 103) (Id "Nothing"))
          taY = TypeAnnDecl $ typeAnn (Span 75 86) (Id "y") schY
          schY = Scheme (Span 79 86) [] tY
          tY = TApp (TCon (Tycon (Span 79 84, KArr Star Star) (Id "Maybe")))
                    (TVar (Tyvar (Span 85 86, Star) (Id "a")))
      [text|
        data Maybe a = Just a | Nothing
        trait X a where
        impl X Int where
          x = let y : Maybe a
              in Nothing
        |] ==> [impl (Span 48 103) [] (IsIn (Span 53 58) (Id "X") [tyInt]) [x]]

    it "can infer kind for type annotations inside impl with constraints" $ do
      let p = IsIn (Span 54 58) (Id "Eq") [tA]
          tA = TVar (Tyvar (Span 57 58, Star) (Id "a"))
          tMaybe = TApp (TCon (Tycon (Span 66 71, KArr Star Star) (Id "Maybe")))
                        (TVar (Tyvar (Span 72 73, Star) (Id "a")))
      [text|
        data Maybe a = Just a | Nothing
        trait Eq a where
        impl Eq a => Eq (Maybe a) where
          |] ==> [impl (Span 49 80) [p] (IsIn (Span 62 73) (Id "Eq") [tMaybe]) []]

    it "returns error during unification failure" $ do
      [text|
        data Maybe a = Nothing | Just a
        trait X a where
        impl X Maybe where
          |] ==> UnificationFail (IKArr (Span 5 12) (IStar sp) (IStar sp))
                                 (IStar (Span 40 41))
      [text|
        data Maybe a = Nothing | Just a
        trait X a where
        impl X (Maybe a) where
          x = let y : Maybe
              in Nothing
          |] ==> UnificationFail (IStar (Span 85 90))
                  (IKArr (Span 5 12) (IStar sp) (IStar sp))

    it "returns error when trying to construct infinite kinds" $
      [text|
        trait X a where
        impl X Int where
          x = let y : a a
              in Nothing
          |] ==> InfiniteKind (Id "k2")
                  (IKArr (Span 47 50) (IKVar (Span 49 50) $ Id "k2")
                                      (IStar (Span 47 50)))

  describe "type signature kind inference" $ parallel $ do
    let mkA ann = TVar (Tyvar (ann, Star) (Id "a"))
        mkMaybe ann = TApp (TCon (Tycon (ann, KArr Star Star) (Id "Maybe")))

    it "can infer kind for type annotations" $ do
      let schA = scheme (Span 4 5) [] (mkA (Span 4 5))
          schF = scheme (Span 4 10) [] tyF
          tyF = arrow (Span 6 8) (mkA (Span 4 5)) (mkA (Span 9 10))
          schMaybe = scheme (Span 36 43) [] tyMaybe
          tyMaybe = mkMaybe (Span 36 41) (mkA (Span 42 43))
      "x : a" ==> typeAnn (Span 0 5) (Id "x") schA
      "f : a -> a" ==> typeAnn (Span 0 10) (Id "f") schF
      [text|
        data Maybe a = Just a | Nothing
        x : Maybe a
        |] ==> typeAnn (Span 32 43) (Id "x") schMaybe

    it "can infer kind for type annotations with constraints" $ do
      let schMap = scheme (Span 61 96) [predFunctor] tyMap
          predFunctor = IsIn (Span 61 70) (Id "Functor")
                          [TVar (Tyvar (Span 69 70, KArr Star Star) (Id "f"))]
          tyMap = arrow (Span 83 85) tyFunc tyFunc'
          tyFunc = arrow (Span 77 79) (TVar (Tyvar (Span 75 76, Star) (Id "a")))
                                      (TVar (Tyvar (Span 80 81, Star) (Id "b")))
          tyFunc' = arrow (Span 90 92) tyFA tyFB
          tyFA = TApp (TVar (Tyvar (Span 86 87, KArr Star Star) (Id "f")))
                      (TVar (Tyvar (Span 88 89, Star) (Id "a")))
          tyFB = TApp (TVar (Tyvar (Span 93 94, KArr Star Star) (Id "f")))
                      (TVar (Tyvar (Span 95 96, Star) (Id "b")))
      [text|
        trait Functor f where
          map : (a -> b) -> f a -> f b
        (<$>) : Functor f => (a -> b) -> f a -> f b
        |] ==> typeAnn (Span 53 96) (Id "<$>") schMap

    it "enriches nested type annotations with kind information" $ do
      let expr = ELet (Span 36 60) decls (num (Span 59 60) 1)
          decls = [TypeAnnDecl $ typeAnn (Span 40 51) (Id "y") sch]
          sch = Scheme (Span 44 51) [] tyY
          tyY = mkMaybe (Span 44 49) (mkA (Span 50 51))
          num ann = ELit ann . LNumber . Number
      [text|
        data Maybe a = Just a | Nothing
        x = let y : Maybe a
            in 1
        |] ==>  binding (Span 32 60) "x" expr

    it "does not keep track of previous kind vars when inferring kinds" $ do
      let schA = scheme (Span 15 16) [] (mkA (Span 15 16))
          schAx = scheme (Span 21 24) [] tyAx
          tyAx = TApp tyA (TCon (Tycon (Span 23 24, Star) (Id "X")))
          tyA = TVar (Tyvar (Span 21 22, KArr Star Star) (Id "a"))
      [text|
        data X = X
        x : a
        y : a X
        |] ==> Module [ TypeAnnDecl $ typeAnn (Span 11 16) (Id "x") schA
                      , TypeAnnDecl $ typeAnn (Span 17 24) (Id "y") schAx
                      ]

    it "returns error during unification failure" $ do
      [text|
        data Maybe a = Just a | Nothing
        x : Maybe
        |] ==> UnificationFail (IStar (Span 36 41))
                               (IKArr (Span 5 12) (IStar sp) (IStar sp))
      [text|
        data Maybe a = Just a | Nothing
        x : Maybe Maybe
        |] ==> UnificationFail (IStar sp) (IKArr (Span 5 12) (IStar sp) (IStar sp))
      [text|
        data Maybe a = Just a | Nothing
        x : Maybe -> Maybe a
        |] ==> UnificationFail (IStar sp) (IKArr (Span 5 12) (IStar sp) (IStar sp))
      [text|
        trait X a where
          x : a Int
        y : X a => a
        |] ==> UnificationFail (IStar (Span 39 40))
                               (IKArr (Span 22 27) (IStar (Span 24 27))
                                                   (IStar (Span 22 27)))

    it "returns error when trying to construct infinite kinds" $
      "x : a a" ==> InfiniteKind (Id "k1")
                                  (IKArr (Span 4 7)
                                    (IKVar (Span 6 7) $ Id "k1")
                                    (IStar (Span 4 7)))

