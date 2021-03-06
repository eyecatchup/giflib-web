module Main where

import Control.Alternative
import Control.Functor (($>))
import Control.Monad.Eff (Eff())
import Control.Monad.Eff.Class (liftEff)
import Control.Monad.Eff.Exception (error, throwException, Exception(..))
import Data.Argonaut (decodeJson, encodeJson)
import Data.Argonaut.Core (JObject(), fromObject)
import Data.Array (map, concat, (!!))
import Data.Bifunctor (bimap)
import Data.DOM.Simple.Document ()
import Data.DOM.Simple.Element (querySelector, appendChild)
import Data.DOM.Simple.Window (document, globalWindow)
import Data.Either (Either(Left, Right))
import Data.Enum (fromEnum)
import Data.Foldable (intercalate)
import Data.Maybe (Maybe(..), fromMaybe)
import Data.Maybe.Unsafe (fromJust)
import Data.Monoid (mempty)
import Data.String (joinWith, trim, split)
import Data.Tuple (Tuple(..))
import Debug.Trace (Trace(), trace)
import Halogen (runUI, Driver(), HalogenEffects())
import Halogen.Component (Component(..))
import Halogen.HTML.Target (URL(), url, runURL)
import Halogen.Signal (SF1(..), stateful)

import qualified Data.Date as Date
import qualified Data.Int as Int
import qualified Data.Date.UTC as Date
import qualified Data.Set as Set
import qualified Data.StrMap as StrMap
import qualified Halogen.HTML as H
import qualified Halogen.HTML.Attributes as A
import qualified Halogen.HTML.Events as A
import qualified Halogen.HTML.Events.Forms as E
import qualified Halogen.HTML.Events.Handler as E
import qualified Halogen.HTML.Events.Monad as E
import qualified MDL as MDL
import qualified MDL.Button as MDL
import qualified MDL.Textfield as MDL
import qualified MDL.Spinner as MDL
import qualified Node.UUID as NUUID
import qualified Web.Firebase as FB
import qualified Web.Firebase.DataSnapshot as DS
import qualified Web.Firebase.Types as FB
import qualified Data.Foreign as Foreign

import Web.Giflib.Types (Tag(), Entry(..), uuid, runUUID)
import Web.Giflib.Internal.Unsafe (unsafePrintId, undefined, unsafeEvalEff)
import Web.Giflib.Internal.Debug (Console(), log)

data LoadingStatus
 = Loading
 | Loaded
 | LoadingError String

instance eqLoadingStatus :: Eq LoadingStatus where
  (==) Loading Loading                    = true
  (==) Loaded Loaded                      = true
  (==) (LoadingError a) (LoadingError b)  = a == b
  (==) _ _                                = false
  (/=) a b                                = not (a == b)

type State = { entries       :: [Entry]       -- ^ All entries matching the tag
             , tag           :: Maybe Tag     -- ^ Currently selected tag, if any
             , newUrl        :: URL           -- ^ New URL to be submitted
             , newTags       :: Set.Set Tag   -- ^ New Tags to be submitted
             , error         :: String        -- ^ Global UI error to be shown
             , loadingStatus :: LoadingStatus -- ^ List loading state
             }

data Action
  = NoOp
  | ResetNewForm
  | LoadingAction LoadingStatus Action
  | UpdateNewURL URL
  | UpdateNewTags String
  | UpdateEntries [Entry]
  | ShowError String

-- TODO: Wrap that in a Reader so we can access this everywhere.
newtype AppConfig = AppConfig { firebase :: FB.Firebase }

data Request
  = AddNewEntry State

type AppEff eff = HalogenEffects ( uuid :: NUUID.UUIDEff
                                 , now :: Date.Now
                                 , firebase :: FB.FirebaseEff | eff)

emptyState :: State
emptyState = { entries: mempty
             , tag: mempty
             -- TODO: Add a Monoid instance to URL
             , newUrl: url mempty
             , newTags: Set.empty
             , error: mempty
             , loadingStatus: Loading
             }

update :: State -> Action -> State
update s' a = updateState a s'
  where
  updateState NoOp s                = s
  updateState ResetNewForm s        = s { newUrl  = url mempty
                                        -- Typechecker doesn't like Set.empty
                                        -- here, I don't know why.
                                        , newTags = Set.fromList []
                                        }
  updateState (LoadingAction l a) s = updateState a $ s { loadingStatus = l }
  updateState (UpdateNewURL e) s    = s { newUrl  = e }
  updateState (UpdateNewTags e) s   = s { newTags = processTagInput e }
  updateState (UpdateEntries e) s   = s { entries = e }
  updateState (ShowError e) s       = s { error   = e }

-- | Handle a request to an external service
handler :: forall eff.
  Request ->
  E.Event (AppEff eff) Action
handler (AddNewEntry s) = do
  id' <- liftEff NUUID.v4
  now <- liftEff Date.now

  let entry = Entry { id: uuid $ show id'
                    , tags: s.newTags
                    , url: s.newUrl
                    , date: now
                    }

  -- TODO: This should ask the Reader for an FB instance
  fb <- liftEff $ FB.newFirebase $ url "https://giflib-web.firebaseio.com/"
  children <- liftEff $ FB.child "entries" fb
  liftEff $ FB.push (Foreign.toForeign $ encodeJson entry) Nothing children
  E.yield $ ResetNewForm

ui :: forall eff. Component (E.Event (AppEff eff)) Action Action
ui = render <$> stateful emptyState update
  where
  render :: State -> H.HTML (E.Event (AppEff eff) Action)
  render st =
    H.div [ A.class_ $ A.className "gla-content" ] $
      [ H.form [ A.onSubmit \_ -> E.preventDefault $> (handler $ (AddNewEntry st))
               , A.class_ $ A.className "gla-layout--margin-h"
               ]
               [ H.div [ A.class_ $ A.className "gla-form--inline-group" ] [
                 MDL.textfield [ E.onInput (A.input UpdateNewURL <<< url)
                               , A.required true ] $
                  MDL.defaultTextfield { id = Just "inp-new-gif"
                                       , label = Just "URL"
                                       , type_ = "url"
                                       } ]
               , H.div [ A.class_ $ A.className "gla-form--inline-group" ] [
                 MDL.textfield [ E.onInput $ A.input UpdateNewTags
                               , A.required true ] $
                   MDL.defaultTextfield { id = Just "inp-new-tags"
                                        , label = Just "Tags"
                                        } ]
               , H.div [ A.class_ $ A.className "gla-form--inline-group" ] [
                 MDL.button $
                   MDL.defaultButton { text = "Add GIF"
                                     , elevation = MDL.ButtonRaised
                                     } ]
               ]
      , MDL.spinner (st.loadingStatus == Loading)
      , H.div [ A.class_ $ A.className "gla-card-holder" ] $ map entryCard st.entries
      ]

    where

    backgroundImage :: String -> A.Styles
    backgroundImage s = A.styles $ StrMap.singleton "backgroundImage" ("url(" ++ s ++ ")")

    entryCard :: Entry -> H.HTML (E.Event (AppEff eff) Action)
    entryCard (Entry e) = H.div
        [ A.classes [ MDL.card, MDL.shadow 3 ]
        , A.key $ runUUID e.id
        ]
        [ H.div [ A.class_ MDL.cardImageContainer
                , A.style $ backgroundImage $ runURL e.url
                ] []
        , H.div [ A.class_ MDL.cardHeading ]
            [ H.h2
                [ A.class_ MDL.cardHeadingText ] [ H.text $ formatEntryTags e ]
            ]
        , H.div [ A.class_ MDL.cardCaption ] [ H.text $ formatEntryDatetime e ]
        , H.div [ A.class_ MDL.cardBottom ]
            [ H.a
                [ A.href $ runURL e.url
                , A.class_ MDL.cardUri
                , A.target "_blank" ] [ H.text $ runURL e.url ]
            ]
        ]

formatEntryDatetime :: forall e. { date :: Date.Date | e } -> String
formatEntryDatetime e =
  intercalate "-" $ [ show <<< Int.toNumber <<< getYear <<< Date.year $ e.date
                    , show <<< (+1) <<< fromEnum <<< Date.month $ e.date
                    , show <<< Int.toNumber <<< getDay <<< Date.dayOfMonth $ e.date ]
  where
    getDay :: Date.DayOfMonth -> Int.Int
    getDay (Date.DayOfMonth i) = i
    getYear :: Date.Year -> Int.Int
    getYear (Date.Year i) = i

formatEntryTags :: forall e. { tags :: Set.Set Tag | e } -> String
formatEntryTags e = joinWith " " $ map (\x -> "#" ++ x) $ Set.toList e.tags

processTagInput :: String -> Set.Set Tag
processTagInput = trim >>> split " " >>> Set.fromList

-- Application Main

main = do
  trace "Booting. Beep. Boop."
  Tuple node driver <- runUI ui

  -- This should be wrapped in an AppEnv, passed through a Reader.
  fb <- FB.newFirebase $ url "https://giflib-web.firebaseio.com/"
  children <- FB.child "entries" fb
  FB.on FB.Value (dscb driver) Nothing children

  doc <- document globalWindow
  el <- querySelector "#app-main" doc
  case el of
    Just e -> appendChild e node
    Nothing -> throwException $ error "Couldn't find #app-main. What've you done to the HTML?"
  trace "Up and running."

  where
    -- TODO: Use Aff instead of Eff for this.
    dscb :: forall req eff. (Action -> eff) -> FB.DataSnapshot -> eff
    dscb driver ds =
      case (Foreign.unsafeReadTagged "Object" $ DS.val ds) >>= decodeEntries of
        Right entries -> driver (LoadingAction Loaded $ UpdateEntries entries)
        Left  err     -> driver $ ShowError $ show err

    decodeEntries :: JObject -> Either Foreign.ForeignError [Entry]
    decodeEntries = bimap Foreign.JSONError id <<< decodeJson <<< fromObject
