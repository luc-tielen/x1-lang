
module X1.Parser.Impl ( parser ) where

import Protolude hiding ( Type, try, functionName )
import X1.Types.Id
import X1.Types.Expr1
import X1.Types.Expr1.Type
import X1.Types.Expr1.Pred
import X1.Types.Expr1.Impl
import X1.Parser.Helpers
import qualified X1.Parser.Scheme as Scheme
import qualified X1.Parser.Pattern as Pattern
import qualified X1.Parser.Expr1 as Expr1
import qualified X1.Parser.Tycon as Tycon
import qualified X1.Parser.Tyvar as Tyvar


parser :: Parser Impl
parser = parser' <?> "impl declaration" where
  parser' = withLineFold $ do
    keyword "impl"
    predicates <- Scheme.predicatesPrefix
    typeInfo <- lexeme' implParser
    kwResult <- keyword' "where"
    case kwResult of
      NoTrailingWS -> pure $ Impl predicates typeInfo []
      TrailingWS -> do
        indent <- indentLevel
        let bindingParser' = withIndent indent (withLineFold bindingParser)
        bindings <- many bindingParser'
        notFollowedBy badlyIndentedDecl <?> badIndentMsg
        pure $ Impl predicates typeInfo bindings
  badlyIndentedDecl = indented bindingParser
  badIndentMsg = "properly indented binding declaration in impl"

implParser :: Parser Pred
implParser = IsIn <$> traitId <*> some (implTypeParser <?> "type")
  where
    traitId = Id <$> lexeme' capitalIdentifier <?> "trait identifier"
    implTypeParser = lexeme' (betweenParens implTypeParser) <|> implType
    implType = computeType <$> tycon <*> many tyvar
    tycon = lexeme' $ TCon <$> Tycon.parser
    tyvar = lexeme' $ do
      notFollowedBy $ chunk "where"
      TVar <$> Tyvar.parser
    computeType con [] = con
    computeType con vars = TApp con vars


-- TODO remove duplication with expr1 parser once type decls are supported in instances
bindingParser :: Parser Binding
bindingParser = try namedFunctionDecl <|> simpleBinding

namedFunctionDecl :: Parser Binding
namedFunctionDecl = do
  (funcName, vars) <- lexeme' functionHead
  body <- E1Lam vars <$> Expr1.parser
  pure $ Binding funcName body
  where
    functionHead = sameLine $ do
      funcName <- lexeme declIdentifier
      vars <- some $ lexeme Pattern.parser
      void $ lexeme assign
      pure (funcName, vars)

simpleBinding :: Parser Binding
simpleBinding = do
  var <- lexeme' declIdentifier
  void $ lexeme' assign
  Binding var <$> Expr1.parser

declIdentifier :: Parser Id
declIdentifier = Id <$> identifier <|> prefixOperator

prefixOperator :: Parser Id
prefixOperator = Id <$> sameLine (betweenParens opIdentifier) <?> "operator"

assign :: Parser Char
assign = char '=' <?> "rest of assignment"
