{-# LANGUAGE AllowAmbiguousTypes #-}
module Web.Api.Http.Effects.Test.Mock (
    MockIO(..)
  , MockSt(..)
  , mockSt
  , MockServer(..)
  , getMockSt
  , putMockSt
  , getMockException
  ) where

import Data.Time (UTCTime(..), Day(..))
import Data.Time.Clock (addUTCTime)
import Data.ByteString.Lazy (ByteString, pack)
import Control.Exception
import Control.Monad
import System.IO (Handle, stdin, stdout)
import System.IO.Error
  ( mkIOError, eofErrorType, doesNotExistErrorType, fullErrorType )
import System.Random
import qualified Network.Wreq as Wreq
import qualified Network.Wreq.Session as WreqS
import Network.HTTP.Client (HttpException)

import Web.Api.Http.Effects



data MockIO st a = MockIO
  { runMockIO :: MockSt st -> (a, MockSt st)
  }

data MockSt st = MockSt
  { __print_log :: [(Handle, String)]
  , __console_out :: [String]
  , __console_in :: ([String], String)
  , __time :: UTCTime
  , __exception :: Maybe SomeException
  , __server :: MockServer st
  , __wreq_session :: WreqS.Session
  , __file_exists :: Bool
  , __file_full :: Bool
  , __file_out :: [ByteString]
  , __file_in :: [ByteString]
  , __random_seed :: MockGen
  , __local :: st
  } deriving Show

mockSt
  :: MockServer st
  -> WreqS.Session
  -> st
  -> MockSt st
mockSt server session st = MockSt
  { __print_log = []
  , __console_out = []
  , __console_in = ([],"")
  , __time = UTCTime (ModifiedJulianDay 0) 0
  , __exception = Nothing
  , __server = server
  , __wreq_session = session
  , __file_exists = True
  , __file_full = False
  , __file_out = []
  , __file_in = []
  , __random_seed = MockGen 6171
  , __local = st
  }

data MockServer st = MockServer
  { __http_get
      :: st
      -> String
      -> (Either HttpException HttpResponse, st)

  , __http_post
      :: st
      -> String
      -> ByteString
      -> (Either HttpException HttpResponse, st)

  , __http_delete
      :: st
      -> String
      -> (Either HttpException HttpResponse, st)
  }

instance Show (MockServer st) where
  show _ = "<MockServer>"


instance Monad (MockIO st) where
  return x = MockIO $ \state -> (x, state)

  x >>= f = MockIO $ \state ->
    let (a, newstate) = runMockIO x state
    in runMockIO (f a) $ newstate
      { __time = addUTCTime 1 (__time newstate) }

instance Applicative (MockIO st) where
  pure = return
  (<*>) = ap

instance Functor (MockIO st) where
  fmap f x = x >>= (return . f)



getMockSt :: MockIO st (MockSt st)
getMockSt = MockIO $ \state -> (state, state)

putMockSt :: MockSt st -> MockIO st ()
putMockSt state = MockIO $ \_ -> ((), state)

putLocalState :: st -> MockIO st ()
putLocalState st = do
  state <- getMockSt
  putMockSt $ state { __local = st }

getMockException :: MockIO st (Maybe SomeException)
getMockException = do
  state <- getMockSt
  return (__exception state)

throwError :: (Exception e) => e -> MockIO st a
throwError e = do
  state <- getMockSt
  putMockSt $ state { __exception = Just $ toException e }
  return undefined



data MockGen = MockGen Int
  deriving Show

instance RandomGen MockGen where
  next (MockGen k) = (abs k, MockGen $ if even k then k`div`2 else 3*k+1)

  split (MockGen k) = (MockGen k, MockGen (k+1))


instance EffectConsole (MockIO st) where
  mhGetEcho _ = return True
  mhSetEcho _ _ = return ()

  mStdIn = return stdin

  mhGetChar _ = return 'y'

  mhGetLine _ = MockIO $ \state ->
    let (stack, def) = __console_in state in
    case stack of
      [] -> (def, state)
      m:ms -> (m, state { __console_in = (ms,def) })

  mStdOut = return stdout

  mhFlush _ = return ()

  mhPutChar _ c = MockIO $ \state ->
    ((), state { __console_out = [c] : __console_out state })

  mhPutStr _ string = MockIO $ \state ->
    ((), state { __console_out = string : __console_out state })

  mhPutStrLn _ string = mPutStr (string ++ "\n")


instance EffectTimer (MockIO st) where
  mThreadDelay _ = return ()

  mGetSystemTime = do
    st <- getMockSt
    return $ __time st


instance EffectTry (MockIO st) where
  mTry x = do
    a <- x
    ex <- getMockException
    case ex >>= fromException of
      Nothing -> return (Right a)
      Just e -> return (Left e)


instance EffectFiles (MockIO st) where
  mReadFile path = do
    st <- getMockSt
    if __file_exists st
      then case __file_in st of
        [] -> throwError $ mkIOError eofErrorType "" Nothing (Just path)
        m:ms -> do
          putMockSt $ st { __file_in = ms }
          return m
      else throwError $ mkIOError doesNotExistErrorType "" Nothing (Just path)

  mWriteFile path contents = do
    st <- getMockSt
    if __file_full st
      then throwError $ mkIOError fullErrorType "" Nothing (Just path)
      else putMockSt $ st { __file_out = contents : __file_out st }

  mFileExists path = do
    st <- getMockSt
    return $ __file_exists st


instance EffectRandom (MockIO st) where
  mRandom = do
    st <- getMockSt
    let (a,seed) = random $ __random_seed st
    putMockSt $ st { __random_seed = seed }
    return a

  mRandomBetween (lo,hi) = do
    st <- getMockSt
    let (a,seed) = randomR (lo,hi) $ __random_seed st
    putMockSt $ st { __random_seed = seed }
    return a


instance EffectHttp (MockIO st) where
  mGetWith _ _ url = do
    st <- getMockSt
    let (r, update) = __http_get (__server st) (__local st) url
    putLocalState update
    return r 

  mPostWith _ _ url payload = do
    st <- getMockSt
    let (r, update) = __http_post (__server st) (__local st) url payload
    putLocalState update
    return r

  mDeleteWith _ _ url = do
    st <- getMockSt
    let (r, update) = __http_delete (__server st) (__local st) url
    putLocalState update
    return r

  mNewSessionState = do
    st <- getMockSt
    return $ __wreq_session st
