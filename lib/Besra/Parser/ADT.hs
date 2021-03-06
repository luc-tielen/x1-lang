
module Besra.Parser.ADT ( parser ) where

import Protolude hiding ( Type )
import Besra.Types.Id
import Besra.Types.Ann
import Besra.Types.Span
import Besra.Types.IR1 ( ADT(..), ADTHead(..), ADTBody, ConDecl(..), Type(..) )
import qualified Besra.Parser.Type as Type
import qualified Besra.Parser.Tycon as Tycon
import qualified Besra.Parser.Tyvar as Tyvar
import Besra.Parser.Helpers


type ADTHead' = ADTHead Parsed
type ADTBody' = ADTBody Parsed
type ConDecl' = ConDecl Parsed
type Type' = Type Parsed

parser :: Parser (ADT Parsed)
parser = do
  startPos <- getOffset
  keyword "data"
  adtHead <- adtHeadParser <?> "name of datatype"
  adtBody <- withDefault [] $ assignChar *> adtBodyParser
  let sp1 = span adtHead
      sp2 = maybe sp1 span $ nonEmpty adtBody
  pure $ ADT (startPos .> sp1 <> sp2) adtHead adtBody
  where assignChar = lexeme $ indented $ char '='

adtHeadParser :: Parser ADTHead'
adtHeadParser = do
  name <- lexeme $ indented Tycon.parser
  vars <- many $ lexeme $ indented Tyvar.parser
  pure $ ADTHead name vars

adtBodyParser :: Parser ADTBody'
adtBodyParser = conDeclParser `sepBy1` pipeChar
  where pipeChar = lexeme $ indented $ char '|'

conDeclParser :: Parser ConDecl'
conDeclParser = do
  startPos <- getOffset
  (sp1, constrName) <- lexeme (withSpan $ Id <$> indented capitalIdentifier) <?> "constructor"
  types <- many (lexeme (indented adtTypeParser) <?> "type")
  let sp = sconcat $ sp1 :| map span types
  pure $ ConDecl (startPos .> sp) constrName types

adtTypeParser :: Parser Type'
adtTypeParser =  con
             <|> var
             <|> Type.parser
  where con = TCon <$> Tycon.parser
        var = TVar <$> Tyvar.parser

