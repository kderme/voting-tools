{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeFamilies #-}

module CLI.Jormungandr where

import Data.Text (Text)
import Data.Functor (void)
import Data.Text as T
import Data.Text.Encoding as T
import Data.Text.IO as TIO
import Data.ByteString (ByteString)
import qualified Data.ByteString.Char8 as BS
import Turtle (ExitCode(ExitSuccess, ExitFailure), Shell, Line, procStrictWithErr, textToLines, select, shell, fromString)
import Control.Monad.IO.Class (MonadIO, liftIO)
import Control.Monad.Cont (runContT)
import Control.Monad.Except (MonadError)

import CLI.Interop (withTextAsFile, stripTrailingNewlines)
import Encoding

import Cardano.API
import Cardano.API.Voting (VotingKeyPublic, AsType(AsVotingKeyPublic))

-- TODO Proper Reified errors for jclicommands, "ShellError [argv] exitcode"

jcliCmd :: MonadIO io => [Text] -> Shell Line -> io Text
jcliCmd args stdIn = do
  (exitCode, stdOut, stdErr) <- procStrictWithErr "/nix/store/05vka73lmpbs9fm179812g930ijymi98-jormungandr/bin/jcli" args stdIn
  case exitCode of
    ExitSuccess      -> pure (stripTrailingNewlines stdOut)
    ExitFailure code -> error $
      "Encountered exit code " <> show code
      <> " while executing \"jcli " <> T.unpack (T.intercalate " " args) <> "\".\n"
      <> "stderr was: " <> T.unpack stdErr <> "\n"
      <> "stdout was: " <> T.unpack stdOut

jcliSign :: MonadIO m => Text -> VotingKeyPublic -> m Text
jcliSign stake_sk votePub = liftIO . (`runContT` pure) $ do
  skFile     <- withTextAsFile (T.unpack stake_sk)
  votePkFile <- withTextAsFile (BS.unpack $ serialiseToRawBytesHex votePub)
  jcliCmd ["key", "sign", "--secret-key", T.pack skFile, T.pack votePkFile] mempty

jcliKeyAddress networkId key prefix = do
  let
    args  = ["address", "account", key, "--prefix", prefix]
    mAddTesting = id
    -- mAddTesting = if networkId /= Mainnet then (<> ["--testing"]) else id
  jcliCmd (mAddTesting args) mempty

jcliKeyPublic :: MonadIO m => Text -> m Text
jcliKeyPublic skey =
  jcliCmd ["key", "to-public"] (toShellInput skey)

toShellInput :: Text -> Shell Line
toShellInput = fromString . T.unpack

jcliKeyToBytes
  :: ( MonadIO m )
  => Text
  -> m Text
jcliKeyToBytes key = jcliCmd ["key", "to-bytes"] (fromString $ T.unpack key)

jcliKeyFromBytes
  :: ( MonadIO m
     , MonadError e m
     , AsDecodeError e
     )
  => ByteString
  -> m Text
jcliKeyFromBytes bytes = liftIO . (`runContT` pure) $ do
  publicKeyFile <- T.pack <$> withTextAsFile (BS.unpack bytes)
  jcliCmd [ "key", "from-bytes", "--type", "ed25519", publicKeyFile ] mempty

jcliValidateSig :: MonadIO m => Text -> Text -> VotingKeyPublic -> m ()
jcliValidateSig publicKey sig votePub = liftIO . (`runContT` pure) $ do
  publicKeyFile <- T.pack <$> withTextAsFile (T.unpack publicKey)
  sigFile       <- T.pack <$> withTextAsFile (T.unpack sig)
  datFile       <- T.pack <$> withTextAsFile (BS.unpack $ serialiseToRawBytesHex votePub)
  void $ jcliCmd [ "key", "verify", "--public-key", publicKeyFile, "--signature", sigFile, datFile ] mempty
