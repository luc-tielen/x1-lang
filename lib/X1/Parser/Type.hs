
module X1.Parser.Type ( parser ) where

import Protolude hiding ( Type, try )
import qualified X1.Parser.Tycon as Tycon
import qualified X1.Parser.Tyvar as Tyvar
import X1.Types.Expr1.Type
import X1.Parser.Helpers
import X1.Types.Id
import X1.Types.Span
import X1.Types.Ann
import Control.Monad.Combinators.Expr


type Type' = Type 'Parsed
-- TODO: upgrade the parsing of types for better precedence handling

parser :: Parser Type'
parser = typeExpr

typeExpr :: Parser Type'
typeExpr = makeExprParser typeTerm typeOperators <?> "type"

typeTerm :: Parser Type'
typeTerm = computeType <$> typeParser' <?> "type"
  where
    typeParser' = typeParser `sepBy1` whitespace'

typeParser :: Parser Type'
typeParser =
  lexeme $  parenthesizedType
        <|> concreteType
        <|> typeVar
  where
    parenthesizedType = do
      (sp, t) <- withSpan $ betweenParens typeExpr
      pure $ TParen sp t
    concreteType = TCon <$> Tycon.parser
    typeVar = TVar <$> Tyvar.parser

typeOperators :: [[Operator Parser Type']]
typeOperators =
  [ [ InfixR arrow ] ]
  where
    arrow :: Parser (Type' -> Type' -> Type')
    arrow = do
      startPos <- getOffset
      void $ keyword "->"
      let sp = Span startPos (startPos + 2)
      pure $ \t1 t2 -> arrow' sp t1 t2
    arrow' sp t1 t2 = TApp (TCon (Tycon sp (Id "->"))) [t1, t2]

computeType :: [Type'] -> Type'
computeType [] = panic "Parse error when parsing type signature."
computeType [t] = t
computeType (t:ts) = TApp t ts

