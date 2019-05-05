
module Test.X1.Parser.Pattern ( module Test.X1.Parser.Pattern ) where

import Protolude hiding ( Type )
import Test.Tasty.Hspec
import Test.X1.Parser.Helpers
import X1.Types.Pattern
import X1.Types.Lit
import X1.Types.Id
import X1.Parser.Pattern ( parser )
import X1.Parser.Types.String
import X1.Parser.Types.Number
import Test.Hspec.Megaparsec hiding (shouldFailWith, succeedsLeaving)


parse :: Text -> ParseResult Pattern
parse = mkParser parser

num :: Int -> Lit
num = LNumber . SInt

str :: Text -> Lit
str = LString . String

var :: Text -> Id
var = Id

(==>) :: Text -> Pattern -> IO ()
a ==> b = parse a `shouldParse` b


spec_patternParseTest :: Spec
spec_patternParseTest = describe "pattern parser" $ parallel $ do
  it "can parse wildcard patterns" $
    "_" ==> PWildcard

  it "can parse literal patterns" $ do
    "123" ==> PLit (num 123)
    "\"abc\"" ==> PLit (str "abc")

  it "can parse variables in pattern" $ do
    "abc" ==> PVar (var "abc")
    "abc123" ==> PVar (var "abc123")

  it "can parse constructors in pattern" $ do
    let pcon x vars = PCon (Id x) $ PVar . var <$> vars
    "True" ==> pcon "True" []
    "(True)" ==> pcon "True" []
    "(A b)" ==> pcon "A" ["b"]
    "(A b c)" ==> pcon "A" ["b", "c"]
    "(A b c D)" ==> PCon (Id "A") [ PVar (var "b")
                                  , PVar (var "c")
                                  , pcon "D" [] ]

  it "can parse as-patterns" $ do
    "abc@def" ==> PAs (var "abc") (PVar (var "def"))
    "a@1" ==> PAs (var "a") (PLit $ num 1)
    "a@_" ==> PAs (var "a") PWildcard

  it "can parse mix of everything" $ do
    let aPat = PAs (var "a") aInnerPat
        aInnerPat = PCon (Id "A") [bPat]
        bPat = PAs (var "b") bInnerPat
        bInnerPat = PCon (Id "B") [PWildcard, PLit $ num 1, PVar $ var "c"]
    "a@(A b@(B _ 1 c))" ==> aPat

  it "fails with readable error message" $ do
    (parse, "") `shouldFailWith` err 0 (ueof <> elabel "pattern")
    (parse, "_abc") `shouldFailWith` err 1 (utok 'a')
    (parse, "_123") `shouldFailWith` err 1 (utok '1')
    (parse, "()") `shouldFailWith` err 1 (utok ')' <> elabel "constructor")
    (parse, "(_a)") `shouldFailWith` err 1 (utok '_' <> elabel "constructor")
    (parse, "(_ a)") `shouldFailWith` err 1 (utok '_' <> elabel "constructor")
    (parse, "(a b)") `shouldFailWith` err 1 (utok 'a' <> elabel "constructor")
    (parse, "(A b") `shouldFailWith` err 4
      (ueof <> etok ')' <> etok '@' <> elabel "pattern" <> elabel "rest of identifier")
    (parse, "a@(A b") `shouldFailWith` err 6
      (ueof <> etok ')' <> etok '@' <> elabel "pattern" <> elabel "rest of identifier")

