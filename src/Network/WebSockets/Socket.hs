-- | Simple module which provides the low-level socket handling in case you want
-- to write a stand-alone 'WebSockets' application.
{-# LANGUAGE OverloadedStrings #-}
module Network.WebSockets.Socket
    ( runServer
    , runWithSocket
    , receiveEnum
    , sendIter
    ) where

import Prelude hiding (catch)

import Control.Concurrent (forkIO)
import Control.Exception (SomeException, catch)
import Control.Monad (forever)
import Control.Monad.Trans (liftIO)

import Data.ByteString (ByteString)
import Data.Enumerator (Enumerator, Iteratee, (>>==), ($$))
import Network.Socket (Socket)
import qualified Data.Enumerator as E
import qualified Network.Socket as S
import qualified Network.Socket.ByteString as SB

import Network.WebSockets.Handshake.Http
import Network.WebSockets.Monad
import Network.WebSockets.Protocol
import Network.WebSockets.Types

-- | Provides a simple server. This function blocks forever. Note that this
-- is merely provided for quick-and-dirty standalone applications, for real
-- applications, you should use a real server.
runServer :: Protocol p
          => String                        -- ^ Address to bind to
          -> Int                           -- ^ Port to listen on
          -> (Request -> WebSockets p ())  -- ^ Application to serve
          -> IO ()                         -- ^ Never returns
runServer host port ws = S.withSocketsDo $ do
    sock <- S.socket S.AF_INET S.Stream S.defaultProtocol
    _ <- S.setSocketOption sock S.ReuseAddr 1
    host' <- S.inet_addr host
    S.bindSocket sock (S.SockAddrInet (fromIntegral port) host')
    S.listen sock 5
    flip catch (closeSock sock) $ forever $ do
        (conn, _) <- S.accept sock
        _ <- forkIO $ runWithSocket conn ws >> return ()
        return ()
  where
    closeSock :: Socket -> SomeException -> IO ()
    closeSock sock _ = S.sClose sock

-- | This function wraps 'runWebSockets' in order to provide a simple API for
-- stand-alone servers.
runWithSocket :: Protocol p
              => Socket -> (Request -> WebSockets p a) -> IO a
runWithSocket s ws = do
    r <- E.run $ receiveEnum s $$
        runWebSocketsWithHandshake defaultWebSocketsOptions ws (sendIter s)
    S.sClose s
    either (error . show) return r

-- | Create an enumerator which reads from a socket and yields the chunks
receiveEnum :: Socket -> Enumerator ByteString IO a
receiveEnum s = E.checkContinue0 $ \loop f -> do
    b <- liftIO $ SB.recv s 4096
    if b == ""  -- empty result means connection closed.
        then E.continue f
        else f (E.Chunks [b]) >>== loop

-- | Create an iterator which writes to a socket
sendIter :: Socket -> Iteratee ByteString IO ()
sendIter s = E.continue go
  where
    go (E.Chunks []) = E.continue go
    go (E.Chunks cs) = do
      -- Voodoo fix: Check the socket being writable before even trying to
      -- write to it.
      --
      -- Actually, this shouldn't be necessary as SB.sendMany should just fail
      -- if the socket isn't writeable. However, without it, we got many
      -- "Couldn't decode text frame as UTF8" errors in the browser (although
      -- the payload is definitely UTF8).
      --
      -- Oh yeah, and there's a race condition, of course.
      b <- liftIO $ S.sIsWritable s
      if b
        then E.tryIO (SB.sendMany s cs) >> E.continue go
        else E.throwError ConnectionClosed
    go E.EOF         = E.yield () E.EOF
