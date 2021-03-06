
{-# LANGUAGE QuasiQuotes #-}

module Test.Besra.Pass.BalanceOperatorsSpec ( module Test.Besra.Pass.BalanceOperatorsSpec ) where

import Protolude hiding ( pass, Type, Fixity )
import qualified Data.Text as T
import Besra.Pass.BalanceOperators
import Besra.Types.IR1 ( Module(..), Decl(..), Impl(..), Expr(..), ExprDecl(..)
                       , Binding(..), Pred(..), Lit(..), Number(..), FixityInfo(..)
                       , Type(..), Tycon(..), Pattern(..) )
import Besra.Types.Id
import Besra.Types.Fixity
import Besra.Types.Ann
import Besra.Parser
import Test.Hspec
import NeatInterpolation
import Test.Besra.Helpers


type Module' = Module Testing
type Decl' = Decl Testing
type Binding' = Binding Testing
type Expr' = Expr Testing
type Type' = Type Testing
type BalanceError' = BalanceError Parsed

runPass :: Text -> IO (Either BalanceError' Module')
runPass input =
  let
    parseResult = parseFile "balance_operators.test" input
    passResult = case parseResult of
      Left err -> panic $ formatError err
      Right result -> pass result
  in
    runExceptT $ stripAnns <$> passResult

class Testable a where
  (==>) :: Text -> a -> IO ()

infixr 0 ==>

instance Testable Module' where
  a ==> b = do
    result <- runPass a
    result `shouldBe` Right b

instance Testable Decl' where
  a ==> b = a ==> Module $ infixDecls "+" "*" ++ [b]

instance Testable Binding' where
  a ==> b = a ==> BindingDecl b

instance Testable Expr' where
  a ==> b = a ==> binding "a" b

instance Testable (BalanceError Testing) where
  a ==> b = do
    result <- runPass a
    first stripAnn result `shouldBe` Left b
      where stripAnn (BadPrecedence fi1 fi2 d) = BadPrecedence fi1 fi2 (stripAnns d)
            stripAnn (InvalidPrefixPrecedence fi d) = InvalidPrefixPrecedence fi (stripAnns d)


c :: Text -> Type'
c = TCon . Tycon emptyAnn . Id

binding :: Text -> Expr' -> Binding'
binding x = Binding emptyAnn (Id x)

num :: Int -> Expr'
num = ELit emptyAnn . LNumber . SInt

app :: Expr' -> [Expr'] -> Expr'
app = EApp emptyAnn

lam :: [Text] -> Expr' -> Expr'
lam vars = ELam emptyAnn (PVar emptyAnn . Id <$> vars)

var :: Text -> Expr'
var = EVar emptyAnn . Id

con :: Text -> Expr'
con = ECon emptyAnn . Id

parens :: Expr' -> Expr'
parens = EParens emptyAnn

op :: Text -> Expr' -> Expr' -> Expr'
op operator = EBinOp emptyAnn (var operator)

infixDecls :: Text -> Text -> [Decl']
infixDecls a b =
  [ FixityDecl $ FixityInfo emptyAnn L 4 (Id a)
  , FixityDecl $ FixityInfo emptyAnn L 5 (Id b)
  ]

fixityTypeToStr :: Fixity -> Text
fixityTypeToStr L = "infixl"
fixityTypeToStr R = "infixr"
fixityTypeToStr M = "infix"

toFixityDeclStr :: Fixity -> Int -> Text -> Text
toFixityDeclStr fixityType fixity op' =
  T.intercalate " " [fixityTypeToStr fixityType, T.pack $ show fixity, op']


spec :: Spec
spec = describe "balance operators pass" $ parallel $ do
  describe "algorithm" $ parallel $ do
    let leftAssoc = op "*" (op "+" (num 1) (num 2)) (num 3)
        rightAssoc = op "+" (num 1) (op "*" (num 2) (num 3))
        mkScript' bindingStr fixTypePlus fixityPlus fixTypeMul fixityMul =
          let fixityPlusStr = toFixityDeclStr fixTypePlus fixityPlus "+"
              fixityMulStr =  toFixityDeclStr fixTypeMul fixityMul "*"
           in [text|
                $fixityPlusStr
                $fixityMulStr
                $bindingStr
                |]
        mkScript = mkScript' "a = 1 + 2 * 3"
        expected fixTypePlus fixityPlus fixTypeMul fixityMul expr =
          Module [ FixityDecl $ FixityInfo emptyAnn fixTypePlus fixityPlus (Id "+")
                 , FixityDecl $ FixityInfo emptyAnn fixTypeMul fixityMul (Id "*")
                 , BindingDecl $ binding "a" expr
                 ]

    it "can handle L+L assoc, = precedence" $
      mkScript L 5 L 5 ==> expected L 5 L 5 leftAssoc

    it "can handle R+R assoc, = precedence" $
      mkScript R 5 R 5 ==> expected R 5 R 5 rightAssoc

    it "can handle < precedence" $ do
      let scenarios = [(a, b) | a <- [L, R, M], b <- [L, R, M], (a, b) /= (M, M)]
      forM_ scenarios $ \(fixTypePlus, fixTypeMul) ->
        mkScript fixTypePlus 4 fixTypeMul 5
          ==> expected fixTypePlus 4 fixTypeMul 5 rightAssoc

    it "can handle > precedence" $ do
      let scenarios = [(a, b) | a <- [L, R, M], b <- [L, R, M], (a, b) /= (M, M)]
      forM_ scenarios $ \(fixTypePlus, fixTypeMul) ->
        mkScript fixTypePlus 6 fixTypeMul 5
          ==> expected fixTypePlus 6 fixTypeMul 5 leftAssoc

    it "cannot handle different assoc, = precedence" $ do
      -- Invalid combinations: L+R, L+M, R+L, R+M, M+L, M+R
      let scenarios = [(a, b) | a <- [L, R, M], b <- [L, R, M], a /= b]
          aBinding = BindingDecl $ binding "a" leftAssoc
      forM_ scenarios $ \(fixTypePlus, fixTypeMul) -> do
        let fiPlus = FI fixTypePlus 5 (Id "+")
            fiMul = FI fixTypeMul 5 (Id "*")
        mkScript fixTypePlus 5 fixTypeMul 5
          ==> BadPrecedence fiPlus fiMul aBinding

    it "cannot handle M+M assoc, = precedence" $ do
      let aBinding = BindingDecl $ binding "a" leftAssoc
          fiPlus = FI M 5 (Id "+")
          fiMul = FI M 5 (Id "*")
      mkScript M 5 M 5 ==> BadPrecedence fiPlus fiMul aBinding

    it "can handle parentheses" $ do
      -- left assoc results in 1 + ((2 + 3) * 4)
      -- right assoc results in 1 + (2 + (3 * 4))
      let leftExpr = op "+" (num 1) (parens $ op "*" (op "+" (num 2) (num 3)) (num 4))
          rightExpr = op "+" (num 1) (parens $ op "+" (num 2) (op "*" (num 3) (num 4)))
          bindingStr = "a = 1 + (2 + 3 * 4)"
      mkScript' bindingStr L 5 L 5 ==> expected L 5 L 5 leftExpr
      mkScript' bindingStr L 5 L 6 ==> expected L 5 L 6 rightExpr

    it "can handle multiple operators" $ do
      -- expr1 = "((1 + 2) * 3) + 4"
      -- expr2 = "(1 + (2 * 3)) + 4"
      -- expr3 = "1 + ((2 * 3) + 4)"
      let expr1 = op "+" (op "*" (op "+" (num 1) (num 2)) (num 3)) (num 4)
          expr2 = op "+" (op "+" (num 1) (op "*" (num 2) (num 3))) (num 4)
          expr3 = op "+" (num 1) (op "+" (op "*" (num 2) (num 3)) (num 4))
          bindingStr = "a = 1 + 2 * 3 + 4"
      mkScript' bindingStr L 5 L 5 ==> expected L 5 L 5 expr1
      mkScript' bindingStr L 5 L 6 ==> expected L 5 L 6 expr2
      mkScript' bindingStr R 5 R 6 ==> expected R 5 R 6 expr3

    it "can handle mix of multiple operators" $ do
      -- expr1 = "(1 + (2 * 3)) + (4 * 5)"
      -- expr2 = "1 + ((2 * 3) + (4 * 5))"
      let expr1 = op "+" (op "+" (num 1) (op "*" (num 2) (num 3))) (op "*" (num 4) (num 5))
          expr2 = op "+" (num 1) (op "+" (op "*" (num 2) (num 3)) (op "*" (num 4) (num 5)))
          bindingStr = "a = 1 + 2 * 3 + 4 * 5"
      mkScript' bindingStr L 5 L 6 ==> expected L 5 L 6 expr1
      mkScript' bindingStr R 5 R 6 ==> expected R 5 R 6 expr2

    it "can handle mix of everything" $ do
      -- expr = "((1 + (2 * 3))) + 4"
      let bindingStr = "a = (1 + 2 * 3) + 4"
          expr = op "+" (parens $ op "+" (num 1) (op "*" (num 2) (num 3))) (num 4)
      mkScript' bindingStr L 5 L 6 ==> expected L 5 L 6 expr

    it "can deal with unary negation" $ do
      let neg = ENeg emptyAnn
          expr1 = op "+" (num 1) (parens $ neg $ num 2)
          expr2 = op "+" (num 1) (neg $ num 2)
          expr3 =  op "+" (neg $ num 1) (num 2)
      mkScript' "a = 1 + (-2)" L 5 L 6 ==> expected L 5 L 6 expr1
      mkScript' "a = 1 + (-2)" L 6 L 6 ==> expected L 6 L 6 expr1
      mkScript' "a = 1 + -2" L 4 L 6 ==> expected L 4 L 6 expr2
      mkScript' "a = -1 + 2" L 6 L 6 ==> expected L 6 L 6 expr3

    it "fails on exprs with unary negation preceded by higher precedence op" $ do
      let decl = BindingDecl $ binding "a" (op "+" (num 1) (ENeg emptyAnn $ num 2))
      mkScript' "a = 1 + -2" L 6 L 6
        ==> InvalidPrefixPrecedence (FI L 6 (Id "+")) decl

  describe "expressions" $ parallel $ do
    it "does nothing to AST without operators" $
      [text|
        infixl 4 +
        infixl 5 *
        a = f 1 (g 2 3)
        |] ==> app (var "f") [num 1, parens $ app (var "g") [num 2, num 3]]

    it "does nothing to parenthesized prefix operators" $
      [text|
        infixl 4 +
        infixl 5 *
        a = 1 * (+) 2 3
        |] ==> op "*" (num 1) (app (var "+") [num 2, num 3])

    it "assumes infixl 9 when precedence is unspecified" $
      [text|
        infixl 4 +
        a = 1 + 2 * 3
        |] ==> Module [ FixityDecl $ FixityInfo emptyAnn L 4 (Id "+")
                      , BindingDecl $ binding "a" $ op "+" (num 1) (op "*" (num 2) (num 3))]

    it "rebalances operators in lambdas" $
      [text|
        infixl 4 +
        infixl 5 *
        a = \b c -> 1 + 2 * 3
        |] ==> lam ["b", "c"] $ op "+" (num 1) (op "*" (num 2) (num 3))

    it "rebalances operators inside function applications" $ do
      [text|
        infixl 4 +
        infixl 5 *
        a = f (1 + 2 * 3) (4 + 5 * 6)
        |] ==> app (var "f")
            [ parens $ op "+" (num 1) (op "*" (num 2) (num 3))
            , parens $ op "+" (num 4) (op "*" (num 5) (num 6))
            ]
      [text|
        infixl 4 +
        infixl 5 *
        a = (1 + 2 * 3) 1 2
        |] ==> app (parens $ op "+" (num 1) (op "*" (num 2) (num 3))) [num 1, num 2]


    it "rebalances operators in binary operator expression" $
      [text|
        infixl 4 +
        infixl 5 *
        a = (1 + 2 * 3) <> (4 + 5 * 6)
        |] ==> op "<>" (parens $ op "+" (num 1) (op "*" (num 2) (num 3)))
                       (parens $ op "+" (num 4) (op "*" (num 5) (num 6)))

    it "rebalances operators in if" $ do
      [text|
        infixl 4 +
        infixl 5 *
        a = if 1 + 2 * 3 then 1 else 1
        |] ==> EIf emptyAnn (op "+" (num 1) (op "*" (num 2) (num 3)))
                              (num 1) (num 1)
      [text|
        infixl 4 +
        infixl 5 *
        a = if 1 then 1 + 2 * 3 else 1
        |] ==> EIf emptyAnn (num 1)
                              (op "+" (num 1) (op "*" (num 2) (num 3)))
                              (num 1)
      [text|
        infixl 4 +
        infixl 5 *
        a = if 1 then 1 else 1 + 2 * 3
        |] ==> EIf emptyAnn (num 1) (num 1)
                              (op "+" (num 1) (op "*" (num 2) (num 3)))

    it "rebalances operators in case" $ do
      [text|
        infixl 4 +
        infixl 5 *
        a = case 1 + 2 * 3 of
              x -> x
        |] ==> ECase emptyAnn (op "+" (num 1) (op "*" (num 2) (num 3)))
                                [ (PVar emptyAnn (Id "x"), var "x")]
      [text|
        infixl 4 +
        infixl 5 *
        a = case 1 of
              x -> 1 + 2 * 3
        |] ==> ECase emptyAnn (num 1)
                [ (PVar emptyAnn (Id "x"), op "+" (num 1) (op "*" (num 2) (num 3)))]

    it "rebalances operators in parenthesized expression" $
      [text|
        infixl 4 +
        infixl 5 *
        a = (1 + 2 * (3 + 4 * 5))
        |] ==> parens (op "+" (num 1) (op "*" (num 2)
                      (parens $ op "+" (num 3) (op "*" (num 4) (num 5)))))

    it "rebalances operators in let" $ do
      let complex x y z = op "+" x (op "*" y z)
          bindingDecl x expr = ExprBindingDecl (binding x expr)
      [text|
        infixl 4 +
        infixl 5 *
        a = let b = 1 + 2 * 3
                c = 4 + 5 * 6
             in b + c * c
        |] ==> ELet emptyAnn [ bindingDecl "b" $ complex (num 1) (num 2) (num 3)
                             , bindingDecl "c" $ complex (num 4) (num 5) (num 6)
                             ]
                             (complex (var "b") (var "c") (var "c"))

    it "takes nested fixity decls inside let into account" $ do
      let complex x y = op "*" (op "+" x y)
          bindingDecl x expr = ExprBindingDecl (binding x expr)
      [text|
        infixl 4 +
        a = let b = 1 + 2 * 3
                infixl 3 *
                c = 4 + 5 * 6
             in b + c * c
        |] ==> Module
                [ FixityDecl $ FixityInfo emptyAnn L 4 (Id "+")
                , BindingDecl $ binding "a" $
                  ELet emptyAnn [ bindingDecl "b" $ complex (num 1) (num 2) (num 3)
                                , ExprFixityDecl $ FixityInfo emptyAnn L 3 (Id "*")
                                , bindingDecl "c" $ complex (num 4) (num 5) (num 6)
                                ]
                      (complex (var "b") (var "c") (var "c"))
                ]
      [text|
        a = let b = 1 + 2 * 3
                infixl 5 *
             in let infixl 4 +
                in 4 + 5 * 6
        |] ==> Module
                [ BindingDecl $ binding "a" $
                  ELet emptyAnn [ bindingDecl "b" $ complex (num 1) (num 2) (num 3)
                                , ExprFixityDecl $ FixityInfo emptyAnn L 5 (Id "*")
                                ]
                    (ELet emptyAnn [ ExprFixityDecl $ FixityInfo emptyAnn L 4 (Id "+")
                                   ]
                          (op "+" (num 4) (op "*" (num 5) (num 6))))
                ]

    it "keeps track of scope of fixity declarations inside multiple let exprs" $
      [text|
        a = let infixl 4 +
                infixl 5 *
             in 1 + 2 * 3
        b = let infixl 4 +
                infixl 3 *
             in 4 + 5 * 6
        |] ==> Module
                [ BindingDecl $ binding "a" $
                  ELet emptyAnn [ ExprFixityDecl $ FixityInfo emptyAnn L 4 (Id "+")
                                , ExprFixityDecl $ FixityInfo emptyAnn L 5 (Id "*")
                                ]
                      (op "+" (num 1) (op "*" (num 2) (num 3)))
                , BindingDecl $ binding "b" $
                  ELet emptyAnn [ ExprFixityDecl $ FixityInfo emptyAnn L 4 (Id "+")
                                , ExprFixityDecl $ FixityInfo emptyAnn L 3 (Id "*")
                                ]
                      (op "*" (op "+" (num 4) (num 5)) (num 6))
                ]

    it "rebalances infix functions" $ do
      let op' operator = EBinOp emptyAnn (con operator)
      [text|
        infixl 4 `plus`
        infixl 5 `Mul`
        a = 1 `plus` 2 `Mul` 3
        |] ==> Module (infixDecls "plus" "Mul"
            ++ [BindingDecl $ binding "a" $ op "plus" (num 1) (op' "Mul" (num 2) (num 3))])

  describe "declarations" $ parallel $ do
    it "rebalances operators in impl declarations" $
      [text|
        infixl 4 +
        infixl 5 *
        impl X A where
          a = 1 + 2 * 3
        |] ==> ImplDecl
                $ Impl emptyAnn [] (IsIn emptyAnn (Id "X") [c "A"])
                          [binding "a" $ op "+" (num 1) (op "*" (num 2) (num 3))]

    it "rebalances operators in binding declaration" $
      [text|
        infixl 4 +
        infixl 5 *
        a = 1 + 2 * 3
        |] ==> op "+" (num 1) (op "*" (num 2) (num 3))

  describe "module" $ parallel $ do
    it "rebalances every expression in a file" $
      [text|
        infixl 4 +
        infixl 5 *
        a = 1 + 2 * 3
        b = 4 + 5 * 6
        |] ==> Module (infixDecls "+" "*"
            ++ [ BindingDecl $ binding "a" $ op "+" (num 1) (op "*" (num 2) (num 3))
               , BindingDecl $ binding "b" $ op "+" (num 4) (op "*" (num 5) (num 6))])

    it "is possible to specify fixity after operator is used" $
      [text|
        a = 1 + 2 * 3
        infixl 4 +
        infixl 5 *
          |] ==> Module ((BindingDecl $ binding "a" $ op "+" (num 1) (op "*" (num 2) (num 3))) : infixDecls "+" "*")

