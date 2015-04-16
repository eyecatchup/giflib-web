module Main where

import Control.Alternative
import Control.Functor (($>))
import Data.Array (map, concat, (!!))
import Data.Maybe (Maybe(..), fromMaybe)
import Data.Maybe.Unsafe (fromJust)
import Data.Monoid (mempty)
import Data.String (joinWith, trim, split)
import Data.Tuple (Tuple(..))

import Halogen (runUI, HalogenEffects())
import Halogen.Component (component, Component(..))
import Halogen.Signal (SF1(..), stateful)
import qualified Halogen.HTML as H
import qualified Halogen.HTML.Attributes as A
import qualified Halogen.HTML.Events as A
import qualified Halogen.HTML.Events.Handler as E
import qualified Halogen.HTML.Events.Forms as E
import qualified Halogen.HTML.Events.Monad as E
import qualified Data.Date as Date
import qualified WSK as WSK
import qualified WSK.Textfield as WSK
import qualified WSK.Button as WSK
import qualified Data.StrMap as StrMap
import qualified Node.UUID as UUID

import Web.Giflib.Types (URI(), Tag(), Entry(..))
import Web.Giflib.Internal.Unsafe (unsafePrintId, undefined)
import Control.Monad.Eff (Eff())
import Control.Monad.Eff.DOM (querySelector, appendChild)
import Control.Monad.Eff.Exception (error, throwException, Exception(..))


type State = { entries :: [Entry]   -- ^ All entries matching the tag
             , tag     :: Maybe Tag -- ^ Currently selected tag, if any
             , newUri  :: String    -- ^ New URI to be submitted
             , newTags :: [Tag]     -- ^ New Tags to be submitted
             }

data Action
  = NoOp
  | NewEntry
  | UpdateNewURI String
  | UpdateNewTags String

data Request
  = AddNewEntry State

emptyState :: State
emptyState = { entries: mempty
             , tag: mempty
             , newUri: mempty
             , newTags: mempty
             }

demoEntries :: [Entry]
demoEntries = [ { id: "CDF20EF7-A181-47B7-AB6B-5E0B994F6176"
                , uri: "http://media.giphy.com/media/JdCz7YXOZAURq/giphy.gif"
                , tags: [ "hamster", "party", "animals" ]
                , date: fromJust $ Date.date 2015 Date.January 1
                }
              , { id: "EA72E9A5-0EFA-44A3-98AA-7598C8E5CD14"
                , uri: "http://media.giphy.com/media/lkimmb3hVhjvWF0KA/giphy.gif"
                , tags: [ "cat", "wiggle", "animals" ]
                , date: fromJust $ Date.date 2015 Date.February 28
                }
              ]

demoState :: State
demoState = emptyState { entries = demoEntries, tag = Just "animals" }

update :: State -> Action -> State
update s' a = updateState a s'
  where
  updateState NoOp s = s
  updateState NewEntry s =
    -- uuid <- UUID.v4
    let e = { id: "FAKE" -- UUID.showuuid uuid
            , tags: s.newTags
            , uri: s.newUri
            , date: fromJust $ Date.date 2015 Date.February 28
            }
    in
    s { entries = (unsafePrintId e) : s.entries }
  updateState (UpdateNewURI e) s = s { newUri = unsafePrintId e }
  updateState (UpdateNewTags e) s = s { newTags = unsafePrintId $ processTagInput e }

-- | Handle a request to an external service
handler :: forall eff.
  Request ->
  E.Event (HalogenEffects (uuid :: UUID.UUIDEff | eff)) Action
handler (AddNewEntry e) = undefined

ui :: forall p eff. Component p (E.Event (HalogenEffects (uuid :: UUID.UUIDEff | eff))) Action Action
ui = component $ render <$> stateful demoState update
  where
  render :: State -> H.HTML p (E.Event (HalogenEffects (uuid :: UUID.UUIDEff | eff)) Action)
  render st =
    H.div [ A.class_ $ A.className "gla-content" ]
      [ H.form [ A.onsubmit \_ -> {- E.preventDefault $> -} pure $ handler $ AddNewEntry st
               , A.class_ $ A.className "gla-layout--margin-h"
               ]
               [ H.div [ A.class_ $ A.className "gla-form--inline-group" ] [
                 WSK.textfield [ E.onInput $ A.input UpdateNewURI ] $
                  WSK.defaultTextfield { id = Just "inp-new-gif"
                                       , label = Just "URI"
                                       , type_ = "url"
                                       } ]
               , H.div [ A.class_ $ A.className "gla-form--inline-group" ] [
                 WSK.textfield [ E.onInput $ A.input UpdateNewTags ] $
                   WSK.defaultTextfield { id = Just "inp-new-tags"
                                        , label = Just "Tags"
                                        } ]
               , H.div [ A.class_ $ A.className "gla-form--inline-group" ] [
                 WSK.button $
                   WSK.defaultButton { text = "Add GIF"
                                     , elevation = WSK.ButtonRaised
                                     } ]
               ]
      , H.div [ A.class_ $ A.className "gla-card-holder" ] $ map entryCard st.entries
      ]

    where

    backgroundImage :: String -> A.Styles
    backgroundImage s = A.styles $ StrMap.singleton "backgroundImage" ("url(" ++ s ++ ")")

    entryCard :: Entry -> H.HTML p (E.Event (HalogenEffects (uuid :: UUID.UUIDEff | eff)) Action)
    entryCard e = H.div
        -- TODO: halogen doesn't support keys at the moment which
        -- would certainly be desirable for diffing perf:
        -- https://github.com/Matt-Esch/virtual-dom/blob/7cd99a160f8d7c9953e71e0b26a740dae40e55fc/docs/vnode.md#arguments
        [ A.classes [WSK.card, WSK.shadow 3]
        ]
        [ H.div [ A.class_ WSK.cardImageContainer
                , A.style $ backgroundImage e.uri
                ] []
        , H.div [ A.class_ WSK.cardHeading ]
            [ H.h2
                [ A.class_ WSK.cardHeadingText ] [ H.text $ formatEntryTags e ]
            ]
        , H.div [ A.class_ WSK.cardCaption ] [ H.text $ formatEntryDatetime e ]
        , H.div [ A.class_ WSK.cardBottom ]
            [ H.a
                [ A.href e.uri
                , A.class_ WSK.cardUri
                , A.target "_blank" ] [ H.text e.uri ]
            ]
        ]

formatEntryDatetime :: forall e. { date :: Date.Date | e } -> String
formatEntryDatetime e = show e.date

formatEntryTags :: forall e. { tags :: [Tag] | e } -> String
formatEntryTags e = joinWith " " $ map (\x -> "#" ++ x) e.tags

processTagInput :: String -> [Tag]
processTagInput = trim >>> split " "

-- Application Main

main = do
  Tuple node driver <- runUI ui
  el <- querySelector "#app-main"
  case el of
    Just e -> appendChild node e
    Nothing -> throwException $ error "Couldn't find #app-main. What've you done to the HTML?"
