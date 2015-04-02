module WSK.Textfield where

import Data.Monoid
import Data.Maybe

import qualified Halogen.HTML as H
import qualified Halogen.HTML.Attributes as A

type Textfield = { type_         :: String
                 , id            :: String
                 , label         :: String
                 , floatingLabel :: Boolean
                 }

textfield :: forall p r node. (H.HTMLRepr node) => Textfield -> node p r
textfield t =
  H.div [ A.classes mainClasses ]
    [ H.input [ A.class_ clsTextfieldInput
              , A.id_ t.id
              , A.type_ t.type_
              ] []
    , H.label [ A.class_ clsLabel, A.for t.id ] [ H.text t.label ]
    ]
  where clsTextfield         = A.className "wsk-textfield"
        clsJsTextfield       = A.className "wsk-js-textfield"
        clsFloatingTextfield = A.className "wsk-textfield--floating-label"
        clsTextfieldInput    = A.className "wsk-textfield__input"
        clsLabel             = A.className "wsk-textfield__label"
        mainClasses =
          [ clsTextfield, clsJsTextfield ] ++
            if t.floatingLabel then [ clsFloatingTextfield ] else []

mip :: forall a b f m. (Monoid (f b), Applicative f) => (a -> b) -> Maybe a -> f b
mip f = maybe mempty (pure . f)
