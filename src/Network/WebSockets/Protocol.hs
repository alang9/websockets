-- | Wrapper for supporting multiple protocol versions
{-# LANGUAGE ExistentialQuantification #-}
module Network.WebSockets.Protocol
    ( Protocol (..)
    , TextProtocol
    , BinaryProtocol
    , close
    , ping
    , pong
    , textData
    , binaryData
    ) where

import qualified Data.ByteString as B

import Network.WebSockets.Types
import Network.WebSockets.Handshake.Http
import qualified Network.WebSockets.Protocol.Unsafe as Unsafe

class Protocol p where
    -- | Unique identifier for us.
    version       :: p -> String

    -- | Version as used in the "Sec-WebSocket-Version " header. This is
    -- usually not the same nor derivable from "version", e.g. for hybi10,
    -- it's "8".
    headerVersion :: p -> B.ByteString

    encodeFrame   :: p -> Encoder p Frame
    decodeFrame   :: p -> Decoder p Frame

    -- | Parse and validate the rest of a request. For hybi10, this is just
    -- validation, but hybi00 also needs to fetch a "security token"
    --
    -- todo: Maybe we should introduce our own simplified error type here. (to
    -- be amended with the RequestHttpPart for the user)
    finishRequest :: p -> RequestHttpPart
                  -> Decoder p (Either HandshakeError Request)

    -- | Implementations of the specification
    implementations :: [p]

class Protocol p => TextProtocol p
class TextProtocol p => BinaryProtocol p

-- | Construct a close message
close :: (TextProtocol p, WebSocketsData a) => a -> Message p
close = Unsafe.close

-- | Construct a ping message
ping :: (BinaryProtocol p, WebSocketsData a) => a -> Message p
ping = Unsafe.ping

-- | Construct a pong message
pong :: (BinaryProtocol p, WebSocketsData a) => a -> Message p
pong = Unsafe.pong

-- | Construct a text message
textData :: (TextProtocol p, WebSocketsData a) => a -> Message p
textData = Unsafe.textData

-- | Construct a binary message
binaryData :: (BinaryProtocol p, WebSocketsData a) => a -> Message p
binaryData = Unsafe.binaryData
