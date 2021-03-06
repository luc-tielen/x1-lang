
module Besra.Parser.Pattern ( parser, clauseParser ) where

import Protolude
import Besra.Parser.Helpers
import Besra.Types.IR1 ( Pattern(..) )
import Besra.Types.Span
import Besra.Types.Ann
import Besra.Types.Id
import qualified Besra.Parser.Lit as Lit


type Pattern' = Pattern Parsed

parser :: Parser Pattern'
parser = parser' <?> "pattern" where
  parser' =  wildcardPattern
         <|> literalPattern
         <|> varOrAsPattern
         <|> conPattern

clauseParser :: Parser Pattern'
clauseParser = parser' <?> "pattern" where
  parser' =  wildcardPattern
         <|> literalPattern
         <|> varOrAsPattern
         <|> clauseConPattern

wildcardPattern :: Parser Pattern'
wildcardPattern = PWildcard . fst <$> p
  where p = withSpan (char '_' <* notFollowedBy (letterChar <|> digitChar))

literalPattern :: Parser Pattern'
literalPattern = uncurry PLit <$> withSpan Lit.parser

conPattern :: Parser Pattern'
conPattern = singleCon <|> multiCon where
  multiCon = do
    (sp, con, pats) <- sameLine $ betweenParens $ do
      (sp, con) <- conParser
      pats <- many (lexeme parser)
      pure (sconcat $ sp :| map span pats, con, pats)
    pure $ PCon sp con pats
  singleCon = do
    (sp, con) <- conParser
    pure $ PCon sp con []

clauseConPattern :: Parser Pattern'
clauseConPattern = betweenParens parser' <|> parser' where
  parser' = do
    (sp, con, pats) <- sameLine $ do
      (sp, con) <- conParser
      pats <- many (lexeme parser)
      pure (sconcat $ sp :| map span pats, con, pats)
    pure $ PCon sp con pats

conParser :: Parser (Ann Parsed, Id)
conParser = withSpan (Id <$> lexeme capitalIdentifier <?> "constructor")

varOrAsPattern :: Parser Pattern'
varOrAsPattern = do
  (sp1, var) <- withSpan $ Id <$> identifier
  optional (char '@' <?> "pattern") >>= \case
    Nothing -> pure $ PVar sp1 var
    Just _ -> do
      (sp2, pat) <- withSpan parser
      pure $ PAs (sp1 <> sp2) var pat

