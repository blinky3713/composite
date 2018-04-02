module Composite.Aeson.Formats.InternalTH
  ( makeTupleDefaults, makeTupleFormats
  ) where

import Composite.Aeson.Base (JsonFormat(JsonFormat), JsonProfunctor(JsonProfunctor))
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.BetterErrors as ABE
import Data.List (foldl')
import Data.Monoid ((<>))
import qualified Data.Vector as V
import Language.Haskell.TH
  ( Name, mkName, newName, tupleDataName
  , Q
  , cxt, clause, normalB
  , Dec, funD, instanceD, sigD, valD
  , Exp(AppE, ConE, VarE), appE, doE, lamE, listE, varE
  , conP, varP, wildP
  , bindS, noBindS
  , Type(AppT, ArrowT, ConT, ForallT, TupleT, VarT), appT, conT, varT
  , TyVarBndr(PlainTV)
  )
import Language.Haskell.TH.Syntax (lift)

djfClassName :: Name
djfClassName = mkName "Composite.Aeson.Formats.Default.DefaultJsonFormat"

djfFunName :: Name
djfFunName = mkName "Composite.Aeson.Formats.Default.defaultJsonFormat"

-- |Splice which inserts the @DefaultJsonFormat@ instances for tuples.
makeTupleDefaults :: Q [Dec]
makeTupleDefaults = traverse makeTupleDefault [2..59]
  where
    makeTupleDefault arity = do
      names <- traverse (newName . ("a" ++) . show) [1..arity]
      let constraints = map (appT (conT djfClassName) . varT) names
          instanceHead = appT (conT djfClassName) (pure $ foldl' AppT (TupleT arity) (map VarT names))
          implName = mkName $ "Composite.Aeson.Formats.Provided.tuple" <> show arity <> "JsonFormat"
      instanceD (cxt constraints) instanceHead
        [ funD (mkName "defaultJsonFormat")
          [ clause
              []
              (normalB (pure $ foldl' (\ lhs _ -> AppE lhs (VarE djfFunName)) (VarE implName) [1..arity]))
              []
          ]
        ]

-- |Splice which inserts the @tupleNJsonFormat@ implementations for tuples.
makeTupleFormats :: Q [Dec]
makeTupleFormats = concat <$> traverse makeTupleFormat [2..59]
  where
    makeTupleFormat arity = do
      tyNames   <- traverse (newName . ("t" ++) . show) [1..arity]
      oNames    <- traverse (newName . ("o" ++) . show) [1..arity]
      iNames    <- traverse (newName . ("i" ++) . show) [1..arity]
      oTupName  <- newName "oTup"
      iTupName  <- newName "iTup"
      valNames  <- traverse (newName . ("v" ++) . show) [1..arity]
      tyErrName <- newName "e"

      let name = mkName $ "tuple" <> show arity <> "JsonFormat"
          tupleType = foldl' AppT (TupleT arity) (map VarT tyNames)
          funType =
            ForallT
              (PlainTV tyErrName : map PlainTV tyNames)
              []
              (foldr ((\l r -> AppT (AppT ArrowT (AppT (AppT (ConT ''JsonFormat) (VarT tyErrName)) l)) r) . VarT)
                     (AppT (AppT (ConT ''JsonFormat) (VarT tyErrName)) tupleType)
                     tyNames)
          oTupImpl =
            lamE
              [conP (tupleDataName arity) (map varP valNames)]
              [| (Aeson.Array . V.fromList) $(listE $ map (\ (varName, oName) -> appE (varE oName) (varE varName)) (zip valNames oNames)) |]
          iTupImpl =
            doE
              $  [ bindS wildP [|
                     ABE.withArray Right >>= \ a ->
                       if V.length a == $(lift arity)
                         then pure ()
                         else fail $(lift $ "expected an array of exactly " <> show arity <> " elements")
                     |]
                 ]
              ++ map ( \ (n, valName, iName) ->
                       bindS (varP valName) [| ABE.nth $(lift (n :: Int)) $(varE iName) |] )
                     (zip3 [0..] valNames iNames)
              ++ [ noBindS (appE (varE 'pure) (pure $ foldl' AppE (ConE (tupleDataName arity)) (map VarE valNames))) ]
      sequence
        [ sigD name (pure funType)
        , funD name
          [ clause
              (map (\ (oName, iName) -> conP 'JsonFormat [conP 'JsonProfunctor [varP oName, varP iName]]) (zip oNames iNames))
              (normalB [| JsonFormat (JsonProfunctor $(varE oTupName) $(varE iTupName)) |])
              [ valD (varP oTupName) (normalB oTupImpl) []
              , valD (varP iTupName) (normalB iTupImpl) []
              ]
          ]
        ]
