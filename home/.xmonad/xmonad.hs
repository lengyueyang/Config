{-# LANGUAGE
    TypeSynonymInstances,
    MultiParamTypeClasses,
    DeriveDataTypeable
    #-}

import Control.Monad
import Codec.Binary.UTF8.String (encodeString)
import Data.Char
import Data.List
import qualified Data.Map as M
import Data.Maybe (isNothing, isJust, catMaybes, fromMaybe)
import Data.Function
import Data.Monoid
import System.Exit
import System.IO
import System.Process
import System.Posix.Process (executeFile)
import System.Posix.Types (ProcessID)
import Text.Printf
import Text.Regex

import XMonad hiding ((|||))
import qualified XMonad.StackSet as W
import XMonad.Util.ExtensibleState as XS
import XMonad.Util.EZConfig
import XMonad.Util.Loggers
import XMonad.Util.NamedWindows (getName)
import XMonad.Util.NamedScratchpad
import XMonad.Util.Paste
import XMonad.Util.Run
import qualified XMonad.Util.Themes as Theme
import XMonad.Util.WorkspaceCompare

import XMonad.Prompt
import XMonad.Prompt.Input
import XMonad.Prompt.Man
import XMonad.Prompt.RunOrRaise
import XMonad.Prompt.Shell
import XMonad.Prompt.Window
import XMonad.Prompt.Workspace

import XMonad.Actions.Commands
import XMonad.Actions.CycleWS
import XMonad.Actions.DynamicWorkspaces
import XMonad.Actions.FloatKeys
import XMonad.Actions.FloatSnap
import XMonad.Actions.GridSelect
import XMonad.Actions.Navigation2D
import qualified XMonad.Actions.Search as S
import XMonad.Actions.Submap
import XMonad.Actions.SpawnOn
import XMonad.Actions.TopicSpace
import XMonad.Actions.UpdatePointer
import XMonad.Actions.WindowBringer
import XMonad.Actions.WindowGo
import XMonad.Actions.WindowMenu
import XMonad.Actions.WithAll (killAll)

import XMonad.Hooks.DynamicLog
import XMonad.Hooks.FadeInactive
import XMonad.Hooks.EwmhDesktops
import XMonad.Hooks.ManageDocks
import XMonad.Hooks.ManageHelpers
import XMonad.Hooks.Place
import XMonad.Hooks.UrgencyHook

import XMonad.Layout.Mosaic
import XMonad.Layout.AutoMaster
import XMonad.Layout.DragPane
import XMonad.Layout.Grid
import XMonad.Layout.LayoutCombinators
import XMonad.Layout.Master
import XMonad.Layout.Maximize
import XMonad.Layout.MultiToggle
import XMonad.Layout.MultiToggle.Instances
import XMonad.Layout.Named
import XMonad.Layout.NoBorders
import XMonad.Layout.PerWorkspace
import XMonad.Layout.Reflect
import XMonad.Layout.Renamed
import XMonad.Layout.ResizableTile
import XMonad.Layout.Tabbed
import XMonad.Layout.WindowNavigation
import XMonad.Layout.WorkspaceDir
import qualified XMonad.Layout.Magnifier as Mag

{-
 - TABBED
 -}

myTabTheme = (Theme.theme Theme.kavonChristmasTheme)
    { fontName   = "DejaVu Sans Mono:pixelsize=16"
    , decoHeight = 20
    }

data TABBED = TABBED deriving (Read, Show, Eq, Typeable)
instance Transformer TABBED Window where
     transform _ x k = k (renamed [Replace "TABBED"] (tabbedAlways shrinkText myTabTheme)) (const x)

{-
 - Navigation2D
 -}

myNavigation2DConfig = defaultNavigation2DConfig { layoutNavigation   = [("Full", centerNavigation)]
                                                 , unmappedWindowRect = [("Full", singleWindowRect)]
                                                 }

myLayout = avoidStruts $
    configurableNavigation (navigateColor "#00aa00") $
    mkToggle1 TABBED $
    mkToggle1 NBFULL $
    mkToggle1 REFLECTX $
    mkToggle1 REFLECTY $
    mkToggle1 MIRROR $
    mkToggle1 NOBORDERS $
    smartBorders $
    --onWorkspaces ["web","irc"] Full $
    Full ||| dragPane Horizontal 0.1 0.3 ||| ResizableTall 1 (3/100) (1/2) [] ||| mosaic 1.5 [7,5,2] ||| autoMaster 1 (1/20) (Mag.magnifier Grid)

doSPFloat = customFloating $ W.RationalRect (1/6) (1/6) (4/6) (4/6)
myManageHook = composeAll $
    [ className =? c --> doShift "web" | c <- ["Firefox"] ] ++
    [ className =? c --> doShift "code" | c <- ["Gvim"] ] ++
    [ className =? c --> doShift "doc" | c <- ["Evince"] ] ++
    [ title =? "newsbeuter" --> doShift "news"] ++
    [ title =? "mutt" --> doShift "mail"] ++
    [ className =? c --> doShift "dict" | c <- ["Goldendict", "Stardict"] ] ++
    [ className =? c --> viewShift "media" | c <- ["feh", "Display"] ] ++
    [ prefixTitle "emacs" --> doShift "emacs" ] ++
    [ className =? c --> doShift "net" | c <- ["Wpa_gui", "TUNET64"] ] ++
    [ prefixTitle "libreoffice" <||> prefixTitle "LibreOffice" --> doShift "office" ] ++
    [ myFloats --> doSPFloat ] ++
    [ manageDocks , namedScratchpadManageHook scratchpads ] ++
    [ className =? c --> ask >>= \w -> liftX (hide w) >> idHook | c <- ["XClipboard"] ]
  where
    prefixTitle prefix = fmap (prefix `isPrefixOf`) title
    viewShift = doF . liftM2 (.) W.greedyView W.shift
    myFloats = foldr1 (<||>)
        [ className =? "Firefox" <&&> fmap (/="Navigator") appName
        , className =? "Nautilus" <&&> fmap (not . isSuffixOf " - File Browser") title
        , fmap (isPrefixOf "sun-") appName
        , fmap (isPrefixOf "Gnuplot") title
        , flip fmap className $ flip elem
            [ "XClock"
            , "Xmessage"
            , "Floating"
            ]
        ]

myDynamicLog h = dynamicLogWithPP $ defaultPP
  { ppCurrent = ap clickable (wrap "^i(/home/ray/.xmonad/icons/default/" ")" . fromMaybe "application-default-icon.xpm" . flip M.lookup myIcons)
  , ppHidden = ap clickable (wrap "^i(/home/ray/.xmonad/icons/gray/" ")" . fromMaybe "application-default-icon.xpm" . flip M.lookup myIcons)
  , ppUrgent = ap clickable (wrap "^i(/home/ray/.xmonad/icons/highlight/" ")" . fromMaybe "application-default-icon.xpm" . flip M.lookup myIcons)
  , ppSep = dzenColor "#0033FF" "" " | "
  , ppWsSep = ""
  , ppTitle  = dzenColor "green" "" . shorten 45
  , ppLayout = flip (subRegex (mkRegex "ReflectX")) "[|]" .
      flip (subRegex (mkRegex "ReflectY")) "[-]" .
      flip (subRegex (mkRegex "Mirror")) "[+]"
  , ppOrder  = \(ws:l:t:exs) -> [t,l,ws]++exs
  , ppSort   = fmap (namedScratchpadFilterOutWorkspace.) (ppSort byorgeyPP)
  , ppExtras = [ dzenColorL "violet" "" $ date "%R %a %y-%m-%d"
               , dzenColorL "orange" "" battery
               ]
  , ppOutput = hPutStrLn h
  }
  where
    clickable w = wrap ("^ca(1,wmctrl -s `wmctrl -d | grep "++w++" | cut -d' ' -f1`)") "^ca()"

{-
 - Bindings
 -}

myMouseBindings (XConfig {XMonad.modMask = modm}) = M.fromList $
    [ ((modm, button1), (\w -> focus w >> mouseMoveWindow w
                                       >> windows W.shiftMaster))
    , ((modm, button2), (\w -> focus w >> windows W.shiftMaster))
    , ((modm, button3), (\w -> focus w >> mouseResizeWindow w
                                       >> windows W.shiftMaster))
    ]

myKeys =
    [ ("M-" ++ m ++ [k], f i)
        | (i, k) <- zip myTopicNames "1234567890-="
        , (f, m) <- [ (switchTopic myTopicConfig, "")
                    , (windows . liftM2 (.) W.view W.shift, "S-")
                    ]
    ]
    ++
    [ ("C-; " ++ m ++ [k], f i)
        | (i, k) <- zip myTopicNames "asdfghjkl;'\""
        , (f, m) <- [ (switchTopic myTopicConfig, "")
                    , (windows . liftM2 (.) W.view W.shift, "S-")
                    ]
    ]
    ++
    [("M-" ++ m ++ k, screenWorkspace sc >>= flip whenJust (windows . f))
        | (k, sc) <- zip ["w", "e", "r"] [0..]
        , (f, m) <- [(W.view, ""), (liftM2 (.) W.view W.shift, "S-")]
    ]
    ++
    [ ("M-S-q", io exitFailure)
    , ("M-S-c", kill)
    , ("M-q", spawn "ghc -e ':m +XMonad Control.Monad System.Exit' -e 'flip unless exitFailure =<< recompile False' && xmonad --restart")

    , ("<Print>", spawn "import /tmp/screen.jpg")
    , ("C-<Print>", spawn "import -window root /tmp/screen.jpg")
    , ("M-<Return>", spawn "urxvtc" >> sendMessage (JumpToLayout "ResizableTall"))
    , ("M-s", spawnSelected defaultGSConfig ["urxvtd -q -f -o", "xterm", "firefox-bin", "LC_ALL= LC_CTYPE=zh_CN.UTF-8 emacs --daemon", "desmume", "VisualBoyAdvance "])
    , ("M-S-i", spawn "xcalib -i -a")
    , ("M-S-l", spawn "xscreensaver-command -lock")
    , ("M-S-k", spawn "xkill")
    , ("<XF86AudioNext>", spawn "mpc_seek forward")
    , ("<XF86AudioPrev>", spawn "mpc_seek backward")
    , ("<XF86AudioRaiseVolume>", spawn "change_volume up")
    , ("<XF86AudioLowerVolume>", spawn "change_volume down")
    , ("<XF86AudioMute>", spawn "amixer set Master mute")
    , ("<XF86AudioPlay>", spawn "mpc toggle")
    , ("<XF86Eject>", spawn "eject")
    , ("M-S-a", sendMessage Taller)
    , ("M-S-z", sendMessage Wider)
    , ("M-f", placeFocused $ withGaps (22, 0, 0, 0) $ smart (0.5,0.5))

    -- window management
    , ("M-n", doTo Next EmptyWS getSortByIndex (windows . liftM2 (.) W.view W.shift))
    , ("M-<Space>", sendMessage NextLayout)
    , ("M-i", sendMessage Shrink)
    , ("M-o", sendMessage Expand)
    , ("M-t", withFocused $ windows . W.sink)
    , ("M-,", sendMessage (IncMasterN 1))
    , ("M-.", sendMessage (IncMasterN (-1)))
    , ("M-b", windowPromptBring myXPConfig)
    , ("M-B", sendMessage ToggleStruts)
    , ("M-d", bringMenu)
    , ("M-y", focusUrgent)
    , ("M-;", switchLayer)
    , ("M-h", windowGo L True)
    , ("M-j", windowGo D True)
    , ("M-k", windowGo U True)
    , ("M-l", windowGo R True)
    , ("M-S-<L>", withFocused (keysResizeWindow (-30,0) (0,0))) --shrink float at right
    , ("M-S-<R>", withFocused (keysResizeWindow (30,0) (0,0))) --expand float at right
    , ("M-S-<D>", withFocused (keysResizeWindow (0,30) (0,0))) --expand float at bottom
    , ("M-S-<U>", withFocused (keysResizeWindow (0,-30) (0,0))) --shrink float at bottom
    , ("M-C-<L>", withFocused (keysResizeWindow (30,0) (1,0))) --expand float at left
    , ("M-C-<R>", withFocused (keysResizeWindow (-30,0) (1,0))) --shrink float at left
    , ("M-C-<U>", withFocused (keysResizeWindow (0,30) (0,1))) --expand float at top
    , ("M-C-<D>", withFocused (keysResizeWindow (0,-30) (0,1))) --shrink float at top
    , ("M-<L>", withFocused (keysMoveWindow (-30,0)))
    , ("M-<R>", withFocused (keysMoveWindow (30,0)))
    , ("M-<U>", withFocused (keysMoveWindow (0,-30)))
    , ("M-<D>", withFocused (keysMoveWindow (0,30)))
    , ("C-; <L>", withFocused $ snapMove L Nothing)
    , ("C-; <R>", withFocused $ snapMove R Nothing)
    , ("C-; <U>", withFocused $ snapMove U Nothing)
    , ("C-; <D>", withFocused $ snapMove D Nothing)

    -- dynamic workspace
    , ("M-C-n", addWorkspacePrompt myXPConfig)
    , ("M-C-r", removeWorkspace)
    , ("M-C-S-r", killAll >> removeWorkspace)

    -- Volume
    , ("C-; 9", spawn "change_volume down")
    , ("C-; 0", spawn "change_volume up")
    , ("C-; m", spawn "change_volume toggle")

    -- preferred cui programs
    , ("C-; C-;", pasteChar controlMask ';')
    , ("C-' C-'", pasteChar controlMask '\'')
    , ("C-' g", namedScratchpadAction scratchpads "ghci")
    , ("C-' l", namedScratchpadAction scratchpads "lua")

    , ("C-' o", namedScratchpadAction scratchpads "ocaml")
    , ("C-' e", namedScratchpadAction scratchpads "erl")
    , ("C-' p", namedScratchpadAction scratchpads "ipython")
    , ("C-' r", namedScratchpadAction scratchpads "pry")
    , ("C-' s", namedScratchpadAction scratchpads "gst")
    , ("C-' j", namedScratchpadAction scratchpads "node")
    , ("C-' f", namedScratchpadAction scratchpads "coffee")
    , ("C-' a", namedScratchpadAction scratchpads "alsamixer")
    , ("C-' c", namedScratchpadAction scratchpads "capture")
    , ("C-' m", namedScratchpadAction scratchpads "mpc")
    , ("C-' h", namedScratchpadAction scratchpads "htop")

    , ("M-C-<Space>", sendMessage $ Toggle NBFULL)
    , ("M-C-t", sendMessage $ Toggle TABBED)
    , ("M-C-x", sendMessage $ Toggle REFLECTX)
    , ("M-C-y", sendMessage $ Toggle REFLECTY)
    , ("M-C-m", sendMessage $ Toggle MIRROR)
    , ("M-C-b", sendMessage $ Toggle NOBORDERS)

    -- prompts
    , ("M-'", workspacePrompt myXPConfig (switchTopic myTopicConfig) )
    , ("M-p c", mainCommandPrompt myXPConfig)
    , ("M-p d", changeDir myXPConfig)
    , ("M-p f", fadePrompt myXPConfig)
    , ("M-p m", manPrompt myXPConfig)
    , ("M-p p", runOrRaisePrompt myXPConfig)
    , ("M-p e", launchApp myXPConfig "evince")
    , ("M-p F", launchApp myXPConfig "feh")
    , ("M-p M-p", runOrRaisePrompt myXPConfig)
    ] ++
    searchBindings

scratchpads =
  map f ["erl", "ghci", "gst", "node", "coffee", "ipython", "lua", "pry", "alsamixer", "htop", "xosview"] ++
  [ NS "ocaml" "urxvtc -T ocaml -e rlwrap ocaml" (title =? "ocaml") doSPFloat
  , NS "agenda" "org-agenda" (title =? "Agenda Frame") orgFloat
  , NS "capture" "org-capture" (title =? "Capture Frame") orgFloat
  , NS "mpc" "urxvtc -T mpc -e ncmpcpp" (title =? "mpc") doCenterFloat
  , NS "eix-sync" "urxvtc -T eix-sync -e sh -c \"sudo eix-sync; read\"" (title =? "eix-sync") doTopFloat
  , NS "getmail" "urxvtc -T getmail -e getmail -r rc0 -r rc1" (title =? "getmail") doTopRightFloat
  ]
  where
    urxvt prog = ("urxvtc -T "++) . ((++) . head $ words prog) . (" -e "++) . (prog++) $ ""
    f s = NS s (urxvt s) (title =? s) doSPFloat
    doTopFloat = customFloating $ W.RationalRect (1/3) 0 (1/3) (1/3)
    doTopLeftFloat = customFloating $ W.RationalRect 0 0 (1/3) (1/3)
    doTopRightFloat = customFloating $ W.RationalRect (2/3) 0 (1/3) (1/3)
    doBottomLeftFloat = customFloating $ W.RationalRect 0 (2/3) (1/3) (1/3)
    doBottomRightFloat = customFloating $ W.RationalRect (2/3) (2/3) (1/3) (1/3)
    doLeftFloat = customFloating $ W.RationalRect 0 0 (1/3) 1
    orgFloat = customFloating $ W.RationalRect (1/2) (1/2) (1/2) (1/2)

myConfig dzen = ewmh $ withNavigation2DConfig myNavigation2DConfig $ withUrgencyHook NoUrgencyHook $ defaultConfig
    { terminal           = "urxvtc"
    , focusFollowsMouse  = False
    , borderWidth        = 1
    , modMask            = mod4Mask
    , workspaces         = myTopicNames
    , normalBorderColor  = "#dbdbdb"
    , focusedBorderColor = "#3939ff"
    , mouseBindings      = myMouseBindings
    , layoutHook         = myLayout
    , manageHook         = myManageHook
    , logHook            = fadeOutLogHook myFadeHook >> updatePointer (Relative 0.5 0.5) >> myDynamicLog dzen
    , startupHook        = checkKeymap (myConfig dzen) myKeys >> spawn "~/bin/start-tiling"
} `additionalKeysP` myKeys

defaultFade = 8/10
data FadeState = FadeState Rational (M.Map Window Rational) deriving (Typeable,Read,Show)
instance ExtensionClass FadeState where
  initialValue = FadeState defaultFade M.empty
  extensionType = PersistentExtension

myFadeHook :: Query Rational
myFadeHook = do
  w <- ask
  FadeState fadeUnfocused fadeSet <- liftX XS.get 
  case M.lookup w fadeSet of
    Just v -> return v
    Nothing -> do
      b <- isUnfocused
      return $ if b then fadeUnfocused else 1

myPromptKeymap = M.union defaultXPKeymap $ M.fromList
                 [
                   ((controlMask, xK_g), quit)
                 , ((controlMask, xK_m), setSuccess True >> setDone True)
                 , ((controlMask, xK_j), setSuccess True >> setDone True)
                 , ((controlMask, xK_h), deleteString Prev)
                 , ((controlMask, xK_f), moveCursor Next)
                 , ((controlMask, xK_b), moveCursor Prev)
                 , ((controlMask, xK_p), moveHistory W.focusDown')
                 , ((controlMask, xK_n), moveHistory W.focusUp')
                 , ((mod1Mask, xK_p), moveHistory W.focusDown')
                 , ((mod1Mask, xK_n), moveHistory W.focusUp')
                 , ((mod1Mask, xK_b), moveWord Prev)
                 , ((mod1Mask, xK_f), moveWord Next)
                 ]

myXPConfig = defaultXPConfig
    { font = "xft:DejaVu Sans Mono:pixelsize=16"
    , bgColor           = "#0c1021"
    , fgColor           = "#f8f8f8"
    , fgHLight          = "#f8f8f8"
    , bgHLight          = "steelblue3"
    , borderColor       = "DarkOrange"
    , promptBorderWidth = 1
    , position          = Top
    , historyFilter     = deleteConsecutive
    , promptKeymap = myPromptKeymap
    }

-- | Like 'spawn', but uses bash and returns the 'ProcessID' of the launched application
spawnBash :: MonadIO m => String -> m ProcessID
spawnBash x = xfork $ executeFile "/bin/bash" False ["-c", encodeString x] Nothing

main = do
    checkTopicConfig myTopicNames myTopicConfig
    d <- openDisplay ""
    let w = fromIntegral $ displayWidth d 0 :: Int
        h = fromIntegral $ displayHeight d 0 :: Int
    let barWidth = h `div` 13
    let barHeight = h `div` 35
    let fontSize = h `div` 54
    dzen <- spawnPipe $ "killall dzen2; dzen2 -x " ++ (show $ barWidth*5) ++ " -h " ++ show barHeight ++ " -ta right -fg '#a8a3f7' -fn 'WenQuanYi Micro Hei-" ++ show fontSize ++ "'"
    -- remind <http://www.roaringpenguin.com/products/remind>
    dzenRem <- spawnBash $ "rem | tail -n +3 | grep . | { read a; while read t; do b[${#b[@]}]=$t; echo $t; done; { echo $a; for a in \"${b[@]}\"; do echo $a; done; } | dzen2 -p -x " ++ show barWidth ++ " -w " ++ (show $ barWidth*4) ++ " -h " ++ show barHeight ++ " -ta l -fg '#a8a3f7' -fn 'WenQuanYi Micro Hei-" ++ show fontSize ++ "' -l ${#b[@]}; }"
    spawn $ "killall trayer; trayer --align left --edge top --expand false --width " ++ show barWidth ++ " --transparent true --tint 0x000000 --widthtype pixel --SetPartialStrut true --SetDockType true --height " ++ show barHeight
    xmonad $ myConfig dzen

{-
 - SearchMap
 -}

searchBindings = [ ("M-S-/", S.promptSearch myXPConfig multi) ] ++
                 [ ("M-/ " ++ name, S.promptSearch myXPConfig e) | e@(S.SearchEngine name _) <- engines, length name == 1 ]
  where
    promptSearch (S.SearchEngine _ site)
      = inputPrompt myXPConfig "Search" ?+ \s ->
      (S.search "firefox" site s >> viewWeb)
    viewWeb = windows (W.view "web")

    mk = S.searchEngine
    engines = [ mk "h" "http://www.haskell.org/hoogle/?q="
      , mk "g" "http://www.google.com/search?num=100&q="
      , mk "w" "http://en.wikipedia.org/wiki/Special:Search?go=Go&search="
      , mk "d" "http://duckduckgo.com/?q="
      , mk "m" "https://developer.mozilla.org/en-US/search?q="
      , mk "e" "http://erldocs.com/R15B/mnesia/mnesia.html?search="
      , mk "r" "http://www.ruby-doc.org/search.html?sa=Search&q="
      , mk "gt" "https://bugs.gentoo.org/buglist.cgi?quicksearch="
      , mk "s" "https://scholar.google.de/scholar?q="
      , mk "dict" "http://www.dict.cc/?s="
      , mk "imdb" "http://www.imdb.com/find?s=all&q="
      , mk "i" "https://ixquick.com/do/search?q="
      , mk "def" "http://www.google.com/search?q=define:"
      , mk "img" "http://images.google.com/images?q="
      , mk "gh" "https://github.com/search?q="
      , mk "bb" "https://bitbucket.org/repo/all?name="
      , mk "alpha" "http://www.wolframalpha.com/input/i="
      , mk "ud" "http://www.urbandictionary.com/define.php?term="
      , mk "rtd" "http://readthedocs.org/search/project/?q="
      , mk "null" "http://nullege.com/codes/search/"
      , mk "sf" "http://sourceforge.net/search/?q="
      , mk "acm" "https://dl.acm.org/results.cfm?query="
      , mk "math" "http://mathworld.wolfram.com/search/?query="
      ]
    multi = S.namedEngine "multi" $ foldr1 (S.!>) engines

{-
 - Topic
 -}

data TopicItem = TI { topicName :: Topic
                    , topicDir  :: Dir
                    , topicAction :: X ()
                    , topicIcon :: FilePath
                    }

myTopicNames :: [Topic]
myTopicNames = map topicName myTopics

myTopicConfig :: TopicConfig
myTopicConfig = TopicConfig
    { topicDirs = M.fromList $ map (\(TI n d _ _) -> (n,d)) myTopics
    , defaultTopicAction = const (return ())
    , defaultTopic = "web"
    , maxTopicHistory = 10
    , topicActions = M.fromList $ map (\(TI n _ a _) -> (n,a)) myTopics
    }

myIcons = M.fromList $ map (\(TI n _ _ i) -> (n,i)) myTopics

myTopics :: [TopicItem]
myTopics =
    [ TI "web" "" (spawn "firefox") "firefox.xpm"
    , TI "code" "" (spawn "gvim") "gvim.xpm"
    , TI "term" "" (urxvt "tmux attach -t default") "xterm.xpm"
    , TI "doc" "Documents/" (spawn "evince") "evince.xpm"
    , TI "office" "Documents/" (return ()) "libreoffice34-base.xpm"
    , TI "news" "" (urxvt "newsbeuter") "irssi.xpm"
    , TI "mail" "" (urxvt "mutt" >> urxvt "newsbeuter") "thunderbird.xpm"
    , TI "dict" "" (spawn "goldendict") "goldendict.xpm"
    , TI "media" "" (return ()) "imagemagick.xpm"
    , TI "emacs" "" (spawn "emacsclient -c -n") "emacs.xpm"
    , TI "net" "" (return ()) "gtk-network.xpm"
    ]
  where
    urxvt prog = spawn . ("urxvtc -T "++) . ((++) . head $ words prog) . (" -e "++) . (prog++) $ ""


myCommands =
    [ ("getmail", namedScratchpadAction scratchpads "getmail")
    , ("wallpaper", safeSpawn "change-wallpaper" [])
    , ("fade", fadePrompt myXPConfig)
    ]

fadePrompt xpc = withFocused $ \w -> do
  mkXPrompt (TitledPrompt "fade to") xpc (\s -> return [show x | x <- [0..10], s `isPrefixOf` show x]) $ \i -> do
    let v = read i :: Int
    FadeState u s <- XS.get
    XS.put . FadeState u $ if all isDigit i && 0 <= v && v <= 10
      then M.insert w (toRational v/10) s
      else M.delete w s


data TitledPrompt = TitledPrompt String

instance XPrompt TitledPrompt where
    showXPrompt (TitledPrompt t)  = t ++ ": "
    commandToComplete _ c   = c
    nextCompletion    _     = getNextCompletion

mkCommandPrompt :: XPConfig -> [(String, X ())] -> X ()
mkCommandPrompt xpc cs = do
    mkXPrompt (TitledPrompt "Command") xpc compl $ \i -> whenJust (find ((==i) . fst) cs) snd
  where
    compl s = return . filter (searchPredicate xpc s) . map fst $ cs

mainCommandPrompt xpc = do
  defs <- defaultCommands
  mkCommandPrompt xpc $ nubBy ((==) `on` fst) $ myCommands ++ defs

{- | Get the user's response to a prompt an launch an application using the
   input as command parameters of the application.-}
launchApp :: XPConfig -> String -> X ()
launchApp config app = mkXPrompt (TitledPrompt app) config (getShellCompl []) $ launch app
  where
    launch :: MonadIO m => String -> String -> m ()
    launch app params = spawn $ app ++ " " ++ completionToCommand (undefined :: Shell) params
