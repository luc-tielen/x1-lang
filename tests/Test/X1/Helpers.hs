
module Test.X1.Helpers ( module Test.X1.Helpers ) where

import Protolude hiding ( Type )
import X1.Types.Expr1.Module
import X1.Types.Expr1.Trait
import X1.Types.Expr1.Impl
import X1.Types.Expr1.TypeAnn
import X1.Types.Expr1.Expr
import X1.Types.Expr1.ADT
import X1.Types.Expr1.Scheme
import X1.Types.Expr1.Pred
import X1.Types.Expr1.Type
import X1.Types.Ann


emptyAnn :: ()
emptyAnn = ()

class StripAnns a where
  type Result a

  stripAnns :: a -> Result a

instance StripAnns (Module ph) where
  type Result (Module ph) = Module 'Testing

  stripAnns (Module decls) =
    Module (stripAnns decls)

instance StripAnns (Decl ph) where
  type Result (Decl ph) = Decl 'Testing

  stripAnns = \case
    TypeAnnDecl typeAnn -> TypeAnnDecl (stripAnns typeAnn)
    DataDecl adt -> DataDecl (stripAnns adt)
    TraitDecl trait -> TraitDecl (stripAnns trait)
    ImplDecl _ impl -> ImplDecl emptyAnn (stripAnns impl)
    BindingDecl binding -> BindingDecl (stripAnns binding)
    FixityDecl _ fixity prio op -> FixityDecl emptyAnn fixity prio op

instance StripAnns (ADT ph) where
  type Result (ADT ph) = ADT 'Testing

  stripAnns (ADT _ adtHead body) =
    ADT emptyAnn (stripAnns adtHead) (stripAnns body)

instance StripAnns (ADTHead ph) where
  type Result (ADTHead ph) = ADTHead 'Testing

  stripAnns (ADTHead con vars) =
    ADTHead (stripAnns con) (stripAnns vars)

instance StripAnns (ConDecl ph) where
  type Result (ConDecl ph) = ConDecl 'Testing

  stripAnns (ConDecl _ name tys) =
    ConDecl emptyAnn name (stripAnns tys)

instance StripAnns a => StripAnns [a] where
  type Result [a] = [Result a]

  stripAnns = map stripAnns

instance StripAnns b => StripAnns (a, b) where
  type Result (a, b) = (a, Result b)

  stripAnns = map stripAnns

instance StripAnns (Trait ph) where
  type Result (Trait ph) = Trait 'Testing

  stripAnns (Trait _ ps p tys) =
    Trait emptyAnn (stripAnns ps) (stripAnns p) (stripAnns tys)

instance StripAnns (Impl ph) where
  type Result (Impl ph) = Impl 'Testing

  stripAnns (Impl _ ps p bindings) =
    Impl emptyAnn (stripAnns ps) (stripAnns p) (stripAnns bindings)

instance StripAnns (Pred ph) where
  type Result (Pred ph) = Pred 'Testing

  stripAnns (IsIn _ name tys) =
    IsIn emptyAnn name (stripAnns tys)

instance StripAnns (Binding ph) where
  type Result (Binding ph) = Binding 'Testing

  stripAnns (Binding _ name expr) =
    Binding emptyAnn name (stripAnns expr)

instance StripAnns (Expr1 ph) where
  type Result (Expr1 ph) = Expr1 'Testing

  stripAnns = \case
    E1Lit _ lit -> E1Lit emptyAnn lit
    E1Var _ var -> E1Var emptyAnn var
    E1Con _ con -> E1Con emptyAnn con
    E1Lam _ pats body -> E1Lam emptyAnn pats (stripAnns body)
    E1App _ f args -> E1App emptyAnn (stripAnns f) (stripAnns args)
    E1BinOp _ op l r -> E1BinOp emptyAnn (stripAnns op) (stripAnns l) (stripAnns r)
    E1Neg _ e -> E1Neg emptyAnn (stripAnns e)
    E1If _ c tr fl -> E1If emptyAnn (stripAnns c) (stripAnns tr) (stripAnns fl)
    E1Case _ e clauses -> E1Case emptyAnn (stripAnns e) (stripAnns clauses)
    E1Let _ decls body -> E1Let emptyAnn (stripAnns decls) (stripAnns body)
    E1Parens _ e -> E1Parens emptyAnn (stripAnns e)

instance StripAnns (ExprDecl ph) where
  type Result (ExprDecl ph) = ExprDecl 'Testing

  stripAnns = \case
    ExprTypeAnnDecl typeAnn ->
      ExprTypeAnnDecl (stripAnns typeAnn)
    ExprBindingDecl binding ->
      ExprBindingDecl (stripAnns binding)
    ExprFixityDecl _ fixity prio op ->
      ExprFixityDecl emptyAnn fixity prio op

instance StripAnns (TypeAnn ph) where
  type Result (TypeAnn ph) = TypeAnn 'Testing

  stripAnns (TypeAnn _ name scheme) =
    TypeAnn emptyAnn name (stripAnns scheme)

instance StripAnns (Scheme ph) where
  type Result (Scheme ph) = Scheme 'Testing

  stripAnns (Scheme _ ps ty) =
    Scheme emptyAnn (stripAnns ps) (stripAnns ty)

instance StripAnns (Type ph) where
  type Result (Type ph) = Type 'Testing

  stripAnns = \case
    TCon tycon -> TCon (stripAnns tycon)
    TVar tycon -> TVar (stripAnns tycon)
    TApp t1 ts -> TApp (stripAnns t1) (stripAnns ts)
    TParen _ t -> TParen emptyAnn (stripAnns t)

instance StripAnns (Tycon ph) where
  type Result (Tycon ph) = Tycon 'Testing

  stripAnns (Tycon _ con) = Tycon emptyAnn con

instance StripAnns (Tyvar ph) where
  type Result (Tyvar ph) = Tyvar 'Testing

  stripAnns (Tyvar _ var) = Tyvar emptyAnn var

