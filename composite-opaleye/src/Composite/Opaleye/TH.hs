module Composite.Opaleye.TH where

import BasicPrelude hiding (lift)
import Composite.Opaleye.Util (constantColumnUsing)
import Control.Lens ((<&>))
import qualified Data.ByteString.Char8 as BSC8
import Data.Profunctor.Product.Default (Default, def)
import Data.Traversable (for)
import Database.PostgreSQL.Simple (ResultError(ConversionFailed, Incompatible, UnexpectedNull))
import Database.PostgreSQL.Simple.FromField (FromField, fromField, typename, returnError)
import Language.Haskell.TH
  ( Q, Name, mkName, nameBase, newName, pprint, reify
  , Info(TyConI), Dec(DataD), Con(NormalC)
  , conT
  , dataD, instanceD
  , lamE, varE, caseE, conE
  , conP, varP, wildP, litP, stringL
  , caseE, match
  , funD, clause
  , normalB, normalGE, guardedB
  , cxt
  )
import Language.Haskell.TH.Syntax (lift)
import Opaleye
  ( Column, Constant, QueryRunnerColumnDefault, PGText, fieldQueryRunnerColumn, queryRunnerColumnDefault
  )

-- FIXME needs doc comment
deriveOpaleyeEnum :: Name -> String -> (String -> Maybe String) -> Q [Dec]
deriveOpaleyeEnum hsName sqlName hsConToSqlValue = do
  let sqlTypeName = mkName $ "PG" ++ nameBase hsName
      sqlType = conT sqlTypeName
      hsType = conT hsName

  rawCons <- reify hsName >>= \ case
    TyConI (DataD _cxt _name _tvVarBndrs _maybeKind cons _derivingCxt) ->
      pure cons
    other ->
      fail $ "expected " <> show hsName <> " to name a data declaration, not:\n" <> pprint other

  nullaryCons <- for rawCons $ \ case
    NormalC conName [] ->
      pure conName
    other ->
      fail $ "expected every constructor of " <> show hsName <> " to be a regular nullary constructor, not:\n" <> pprint other

  let conPairs = nullaryCons <&> \ conName ->
        (conName, fromMaybe (nameBase conName) (hsConToSqlValue (nameBase conName)))

  sqlTypeDecl <- dataD (cxt []) sqlTypeName [] Nothing [] (cxt [])

  fromFieldInst <- instanceD (cxt []) [t| FromField $hsType |] . (:[]) $ do
    field <- newName "field"
    mbs   <- newName "mbs"
    tname <- newName "tname"
    other <- newName "other"

    let bodyCase = caseE (varE mbs) $
          [ match
              wildP
              (guardedB [ normalGE [| $(varE tname) /= $(lift sqlName) |]
                                   [| returnError Incompatible $(varE field) "" |] ])
              []
          ] ++
          (
            conPairs <&> \ (conName, value) ->
              match
                [p| Just $(litP $ stringL value) |]
                (normalB [| pure $(conE conName) |])
                []
          ) ++
          [ match 
              [p| Just $(varP other) |]
              (normalB [| returnError ConversionFailed $(varE field) ("Unexpected " <> $(lift sqlName) <> " value: " <> BSC8.unpack $(varE other)) |])
              []
          , match
              [p| Nothing |]
              (normalB [| returnError UnexpectedNull $(varE field) "" |])
              []
          ]

    funD 'fromField
      [ clause
          [varP field, varP mbs]
          (normalB [|
            do
              $(varP tname) <- typename $(varE field)
              $bodyCase
            |])
          []
      ]

  queryRunnerColumnDefaultInst <- instanceD (cxt []) [t| QueryRunnerColumnDefault $sqlType $hsType |] . (:[]) $
    funD 'queryRunnerColumnDefault
      [ clause
          []
          (normalB [| fieldQueryRunnerColumn |])
          []
      ]

  defaultInst <- instanceD (cxt []) [t| Default Constant $hsType (Column $sqlType) |] . (:[]) $ do
    s <- newName "s"
    let body = lamE [varP s] $
          caseE (varE s) $
            conPairs <&> \ (conName, value) ->
              match
                (conP conName [])
                (normalB $ lift value)
                []

    funD 'def
      [ clause
          []
          (normalB [| constantColumnUsing (def :: Constant String (Column PGText)) $body |])
          []
      ]

  pure [sqlTypeDecl, fromFieldInst, queryRunnerColumnDefaultInst, defaultInst]

