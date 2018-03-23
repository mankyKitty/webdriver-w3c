{- |
Module      : Web.Api.Http.Assert
Description : Mini language for making falsifiable assertions.
Copyright   : 2018, Automattic, Inc.
License     : GPL-3
Maintainer  : Nathan Bloomfield (nbloomf@gmail.com)
Stability   : experimental
Portability : POSIX

`WebDriver` sessions are most often tests of some other system. In this module we make "assertions" first class objects.
-}

{-# LANGUAGE RecordWildCards #-}
module Web.Api.Http.Assert (
  -- * Assertions
    Assertion()
  , AssertionResult(..)
  , isSuccess
  , showAssertion
  , success
  , failure

  -- * The `Assert` Class
  , Assert(..)
  , TestTree(..)
  , runTestTree

  -- * Assertion Summaries
  , AssertionSummary()
  , summarize
  , summarizeAll
  , printSummary

  -- * Basic Assertions
  , assertSuccessIf
  , assertSuccess
  , assertFailure
  , assertTrue
  , assertFalse
  , assertEqual
  , assertNotEqual
  , assertIsSubstring
  , assertIsNotSubstring
  , assertIsNamedSubstring
  , assertIsNotNamedSubstring
  ) where

import Data.List (unwords, isInfixOf)



-- | An `Assertion` consists of the following:
--
-- * A human-readable statement being asserted, which may be either true or false.
-- * A result (either success or failure).
-- * A context, representing /where/ the assertion was made, to assist in debugging.
-- * A comment, representing /why/ the assertion was made, also to assist in debugging.
--
-- To construct assertions outside this module, use `success` and `failure`.

data Assertion = Assertion
  { __assertion :: String
  , __assertion_comment :: String
  , __assertion_context :: String
  , __assertion_result :: AssertionResult
  } deriving (Eq, Show)

-- | Type representing the result (success or failure) of an evaluated assertion.
data AssertionResult
  = AssertSuccess | AssertFailure
  deriving (Eq, Show)

-- | Detects successful assertions.
isSuccess :: Assertion -> Bool
isSuccess a = AssertSuccess == __assertion_result a


-- | Basic string representation of an assertion.
showAssertion :: Assertion -> String
showAssertion Assertion{..} =
  case __assertion_result of
    AssertSuccess -> 
      unwords
        [ "\x1b[1;32mValid Assertion\x1b[0;39;49m in"
        , __assertion_context
        , "\nassertion: " ++ __assertion
        , "\ncomment: " ++ __assertion_comment
        ]
    AssertFailure ->
      unwords
        [ "\x1b[1;31mInvalid Assertion\x1b[0;39;49m in"
        , __assertion_context
        , "\nassertion: " ++ __assertion
        , "\ncomment: " ++ __assertion_comment
        ]

-- | Construct a successful assertion.
success
  :: String -- ^ Statement being asserted (the /what/)
  -> String -- ^ Context of the assertion (the /where/)
  -> String -- ^ An additional comment (the /why/)
  -> Assertion
success statement context comment = Assertion
  { __assertion = statement
  , __assertion_comment = comment
  , __assertion_context = context
  , __assertion_result = AssertSuccess
  }

-- | Construct a failed assertion.
failure
  :: String -- ^ Statement being asserted (the /what/)
  -> String -- ^ Context of the assertion (the /where/)
  -> String -- ^ An additional comment (the /why/)
  -> Assertion
failure statement context comment = Assertion
  { __assertion = statement
  , __assertion_comment = comment
  , __assertion_context = context
  , __assertion_result = AssertFailure
  }



-- | Assertions are made and evaluated inside some larger named context, represented by the `Assert` class.

class Assert m where
  -- | Make an assertion.
  assert :: Assertion -> m ()

  -- | Retrieve the context of an assertion.
  assertionContext :: m String

  -- | Enter a new local context.
  nestContext :: String -> m a -> m a


-- | Generic boolean assertion; asserts success if @Bool@ is true and failure otherwise.
assertSuccessIf
  :: (Monad m, Assert m)
  => Bool
  -> String -- ^ Statement being asserted (the /what/)
  -> String -- ^ An additional comment (the /why/)
  -> m ()
assertSuccessIf p statement comment = do
  context <- assertionContext
  assert $
    (if p then success else failure)
    statement context comment

-- | Assertion that always succeeds.
assertSuccess
  :: (Monad m, Assert m)
  => String -- ^ An additional comment (the /why/)
  -> m ()
assertSuccess = assertSuccessIf True "Success!"

-- | Assertion that always fails.
assertFailure
  :: (Monad m, Assert m)
  => String -- ^ An additional comment (the /why/)
  -> m ()
assertFailure = assertSuccessIf False "Failure :("

-- | Succeeds if @Bool@ is `True`.
assertTrue
  :: (Monad m, Assert m)
  => Bool
  -> String -- ^ An additional comment (the /why/)
  -> m ()
assertTrue p = assertSuccessIf (p == True)
  (show p ++ " is True")

-- | Succeeds if @Bool@ is `False`.
assertFalse
  :: (Monad m, Assert m)
  => Bool
  -> String -- ^ An additional comment (the /why/)
  -> m ()
assertFalse p = assertSuccessIf (p == False)
  (show p ++ " is False")

-- | Succeeds if the given @t@s are equal according to their `Eq` instance.
assertEqual
  :: (Monad m, Assert m, Eq t, Show t)
  => t
  -> t
  -> String -- ^ An additional comment (the /why/)
  -> m ()
assertEqual x y = assertSuccessIf (x == y)
  (show x ++ " is equal to " ++ show y)

-- | Succeeds if the given @t@s are not equal according to their `Eq` instance.
assertNotEqual
  :: (Monad m, Assert m, Eq t, Show t)
  => t
  -> t
  -> String -- ^ An additional comment (the /why/)
  -> m ()
assertNotEqual x y = assertSuccessIf (x /= y)
  (show x ++ " is not equal to " ++ show y)

-- | Succeeds if the first list is an infix of the second, according to their `Eq` instance.
assertIsSubstring
  :: (Monad m, Assert m, Eq a, Show a)
  => [a]
  -> [a]
  -> String -- ^ An additional comment (the /why/)
  -> m ()
assertIsSubstring x y = assertSuccessIf (isInfixOf x y)
  (show x ++ " is a substring of " ++ show y)

-- | Succeeds if the first list is not an infix of the second, according to their `Eq` instance.
assertIsNotSubstring
  :: (Monad m, Assert m, Eq a, Show a)
  => [a]
  -> [a]
  -> String -- ^ An additional comment (the /why/)
  -> m ()
assertIsNotSubstring x y = assertSuccessIf (not $ isInfixOf x y)
  (show x ++ " is not a substring of " ++ show y)

-- | Succeeds if the first list is an infix of the second, named list, according to their `Eq` instance. This is similar to `assertIsSubstring`, except that the "name" of the second list argument is used in reporting failures. Handy if the second list is very large -- say the source of a webpage.
assertIsNamedSubstring
  :: (Monad m, Assert m, Eq a, Show a)
  => [a]
  -> ([a],String)
  -> String -- ^ An additional comment (the /why/)
  -> m ()
assertIsNamedSubstring x (y,name) = assertSuccessIf (isInfixOf x y)
  (show x ++ " is a substring of " ++ name)

-- | Succeeds if the first list is not an infix of the second, named list, according to their `Eq` instance. This is similar to `assertIsNotSubstring`, except that the "name" of the second list argument is used in reporting failures. Handy if the second list is very large -- say the source of a webpage.
assertIsNotNamedSubstring
  :: (Monad m, Assert m, Eq a, Show a)
  => [a]
  -> ([a],String)
  -> String -- ^ An additional comment (the /why/)
  -> m ()
assertIsNotNamedSubstring x (y,name) = assertSuccessIf (not $ isInfixOf x y)
  (show x ++ " is not a substring of " ++ name)



-- | `Assertion`s are the most granular kind of "test" this library deals with. Typically we'll be interested in sets of many assertions. A single test case will include one or more assertions, which for reporting purposes we'd like to summarize. The summary for a list of assertions will include the number of successes, the number of failures, and the actual failures. Modeled this way assertion summaries form a monoid, which is handy.

data AssertionSummary = AssertionSummary
  { __num_successes :: Integer
  , __num_failures :: Integer
  , __failures :: [Assertion]
  } deriving (Eq, Show)

instance Monoid AssertionSummary where
  mempty = AssertionSummary 0 0 []

  mappend x y = AssertionSummary
    { __num_successes = __num_successes x + __num_successes y
    , __num_failures = __num_failures x + __num_failures y
    , __failures = __failures x ++ __failures y
    }

-- | Summarize a single assertion.
summary :: Assertion -> AssertionSummary
summary x = AssertionSummary
  { __num_successes = if isSuccess x then 1 else 0
  , __num_failures = if isSuccess x then 0 else 1
  , __failures = if isSuccess x then [] else [x]
  }

-- | Summarize a list of `Assertion`s.
summarize :: [Assertion] -> AssertionSummary
summarize = mconcat . map summary

-- | Summarize a list of `AssertionSummary`s.
summarizeAll :: [AssertionSummary] -> AssertionSummary
summarizeAll = mconcat

-- | Very basic string representation of an `AssertionSummary`.
printSummary :: AssertionSummary -> IO ()
printSummary AssertionSummary{..} = do
  mapM_ (putStrLn . showAssertion) __failures
  putStrLn $ "Assertions: " ++ show (__num_successes + __num_failures)
  putStrLn $ "Failures: " ++ show __num_failures



-- | The `TestTree` type is for modeling hierarchies of test cases, each consisting of one or more assertions. Cribbed from the HUnit library.

data TestTree u
  -- | A single test case.
  = TestCase u

  -- | A list of test cases.
  | TestGroup [TestTree u]

  -- | A label for a tree of test cases.
  | TestLabel String (TestTree u)

-- | Flattens a tree of monadic tests, using `TestLabel`s to nest context.
runTestTree
  :: (Monad m, Assert m)
  => TestTree (m ())
  -> m ()
runTestTree suite = case suite of
  TestCase test -> test
  TestGroup group ->
    mapM_ runTestTree group
  TestLabel label test ->
    nestContext label $ runTestTree test
