module Test.Main where

import Test.Unit
import Web.Giflib.Types (Entry(..))
import Test.Fixtures (entriesJson, entriesRecord)
import Data.Argonaut (decodeJson, jsonParser)
import Data.Either (Either(), isRight)
import Data.Either.Unsafe (fromRight, fromLeft)

import Debug.Trace
import Control.Monad.Eff.Class
import Web.Giflib.Internal.Debug
import Web.Giflib.Internal.Unsafe

main = runTest do
    test "decode a list of entries" do
        let result = decodeEntries entriesJson
        assert "Result could be parsed" $ isRight result
        assert "Decoded entry matches record" $ (unsafePrintId $ fromRight result) == entriesRecord

decodeEntries :: String -> Either String [Entry]
decodeEntries v = jsonParser v >>= decodeJson
