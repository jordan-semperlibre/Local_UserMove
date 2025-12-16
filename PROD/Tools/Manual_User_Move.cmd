@ECHO Off
REM Version 2.8

SETLOCAL enabledelayedexpansion

Set "PROFILE_ROOT=C:\Users"
Set "PROFILE_COUNT=0"
for /f "tokens=1 delims==" %%A in ('set PROFILE_NAME_ 2^>nul') do set "%%A="
for /f "delims=" %%P in ('dir /b /ad "%PROFILE_ROOT%"') do (
    CALL :ShouldIncludeProfile "%%~P"
    IF "!PROFILE_INCLUDE!"=="1" (
        set /a PROFILE_COUNT+=1
        set "PROFILE_NAME_!PROFILE_COUNT!=%%~P"
    )
)
IF !PROFILE_COUNT! GTR 0 (
    ECHO Available user profiles under %PROFILE_ROOT%:
    for /f "tokens=1* delims==" %%A in ('set PROFILE_NAME_') do (
        set "PROFILE_NUM=%%A"
        set "PROFILE_NAME=%%B"
        set "PROFILE_NUM=!PROFILE_NUM:PROFILE_NAME_=!"
        echo   !PROFILE_NUM!^) !PROFILE_NAME!
    )
    ECHO.
) ELSE (
    ECHO No user profiles detected under %PROFILE_ROOT% after filtering exclusions.
    ECHO.
)

Set "TARGET_USER_ID=%USERNAME%"
Set "TARGET_SELECTION="
Set /P TARGET_SELECTION=Select profile by number or type user ID. Press Enter to use current user (%USERNAME%): 
IF NOT DEFINED TARGET_SELECTION (
    Set "TARGET_USER_ID=%USERNAME%"
    Set "TARGET_USERPROFILE=%USERPROFILE%"
) ELSE (
    Set "TARGET_SELECTION_VALUE=!TARGET_SELECTION!"
    Set "TARGET_USER_ID="
    Set "NON_NUMERIC="
    for /f "delims=0123456789" %%A in ("!TARGET_SELECTION_VALUE!") do set "NON_NUMERIC=%%A"
    IF NOT DEFINED NON_NUMERIC (
        Set "LOOKUP_KEY=PROFILE_NAME_!TARGET_SELECTION_VALUE!"
        for /f "tokens=1* delims==" %%B in ('set "!LOOKUP_KEY!" 2^>nul') do (
            if /i "%%B"=="!LOOKUP_KEY!" set "TARGET_USER_ID=%%C"
        )
        Set "LOOKUP_KEY="
    )
    IF NOT DEFINED TARGET_USER_ID (
        Set "TARGET_USER_ID=!TARGET_SELECTION_VALUE!"
    )
    CALL :IsExcludedProfile "!TARGET_USER_ID!"
    IF "!PROFILE_EXCLUDED!"=="1" (
        CLS
        color 40
        @ECHO.
        @ECHO.
        ECHO Profile "!TARGET_USER_ID!" is excluded from selection. Exiting script.
        @ECHO.
        @ECHO.
        Pause
        color 07
        GOTO Quit
    )
    IF /I "!TARGET_USER_ID!"=="%USERNAME%" (
        Set "TARGET_USERPROFILE=%USERPROFILE%"
    ) ELSE (
        Set "TARGET_USERPROFILE=%PROFILE_ROOT%\!TARGET_USER_ID!"
    )
    IF NOT EXIST "!TARGET_USERPROFILE!" (
        CLS
        color 40
        @ECHO.
        @ECHO.
        ECHO User profile "!TARGET_USERPROFILE!" was not found. Exiting script.
        @ECHO.
        @ECHO.
        Pause
        color 07
        GOTO Quit
    )
)
Set "TARGET_APPDATA=!TARGET_USERPROFILE!\AppData\Roaming"
Set "TARGET_LOCALAPPDATA=!TARGET_USERPROFILE!\AppData\Local"

Set mlocal="C:\MOVEME\local\/"
Set mroaming="C:\MOVEME\roaming\/"
Set movescript="\\bfs-fs-p02\endusersoftware\jordan\SCRIPTS"
Set sticky_notes="%TARGET_LOCALAPPDATA%\Packages\Microsoft.MicrosoftStickyNotes_8wekyb3d8bbwe\LocalState"
Set documents="%TARGET_USERPROFILE%\Documents"
Set pictures="%TARGET_USERPROFILE%\Pictures"
Set desktop="%TARGET_USERPROFILE%\Desktop"
Set edge="%TARGET_LOCALAPPDATA%\Microsoft\Edge\User Data\Default"
Set chrome="%TARGET_LOCALAPPDATA%\Google\Chrome\User Data\Default"
::folder path for qaccess changed in Win 11 "%TARGET_USERPROFILE%\AppData\Roaming\Microsoft\Windows\Recent items\AutomaticDestinations"
Set qAccess="%TARGET_APPDATA%\Microsoft\Windows\Recent\AutomaticDestinations"
Set sig="%TARGET_APPDATA%\Microsoft\Signatures"
Set moveme="C:\MOVEME"
Set snagit="%TARGET_LOCALAPPDATA%\TechSmith\SnagIt\DataStore"
Set firefox="%TARGET_APPDATA%\Mozilla\Firefox\Profiles"
Set teams="%TARGET_APPDATA%\Microsoft\Teams\Backgrounds\Uploads"
Set PCOMM="C:\Program Files (x86)\IBM\Personal Communications"
Set office="%TARGET_LOCALAPPDATA%\Microsoft\Office"
Set office_ribbon="%TARGET_APPDATA%\Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar"
Set "TEMP_HIVE_ROOT=HKU\tempuser"
Set "MAPPED_DRIVES_EXPORTED=0"
Set "OPEN_NOTEBOOKS_EXPORTED=0"


CLS
CHOICE /N /C:123 /M "Make a selection (1- Quit, 2 - Import files into new PC, or 3 - Export files from old PC)"%1
IF %ERRORLEVEL% ==3 GOTO three
IF %ERRORLEVEL% ==2 GOTO two
IF %ERRORLEVEL% ==1 GOTO QQuit
IF %ERRORLEVEL% ==0 GOTO zero
Pause
GOTO END


REM ******************************************Exports Section ********************************************************



:three
CLS
@ECHO.
ECHO You have chosen to EXPORT DATA from this PC.
@ECHO.
@ECHO.
@ECHO.
@ECHO.
ECHO All files and folders will be placed in C:\MOVEME, you will need to move this folder to a External DATA drive.
@ECHO.
@ECHO.
Pause
CLS


C:

mkdir C:\MOVEME 2> nul
net use >> C:\MOVEME\shareddrives.txt

GOTO ERegistryExports


:ERegistryExports
Set "NTUSER_PATH=!TARGET_USERPROFILE!\NTUSER.DAT"
reg unload !TEMP_HIVE_ROOT! >nul 2>&1
if exist "!NTUSER_PATH!" (
    reg load !TEMP_HIVE_ROOT! "!NTUSER_PATH!" >nul 2>&1
    if errorlevel 1 (
        ECHO Unable to load registry hive for !TARGET_USER_ID!. Skipping mapped drive and OneNote exports.
    ) else (
        CALL :ExportMappedDrives
        CALL :ExportOpenNotebooks
        reg unload !TEMP_HIVE_ROOT! >nul 2>&1
        if errorlevel 1 (
            ECHO Warning: registry hive !TEMP_HIVE_ROOT! did not unload cleanly. Verify before rerunning.
        )
    )
) else (
    ECHO NTUSER.DAT not found for !TARGET_USER_ID!. Skipping mapped drive and OneNote exports.
)
Set "NTUSER_PATH="
GOTO EOffice


:ExportMappedDrives
Set "MAPPED_DRIVES_FILE=C:\MOVEME\mappeddrives.txt"
del "!MAPPED_DRIVES_FILE!" >nul 2>&1
reg query !TEMP_HIVE_ROOT!\Network >nul 2>&1
if errorlevel 1 (
    ECHO No mapped drive registry data found for !TARGET_USER_ID! or export failed.
) else (
    for %%L in (A B C D E F G H I J K L M N O P Q R S T U V W X Y Z) do (
        reg query "!TEMP_HIVE_ROOT!\Network\%%L" >nul 2>&1
        if not errorlevel 1 (
            for /f "skip=2 tokens=1,2,*" %%H in ('reg query "!TEMP_HIVE_ROOT!\Network\%%L" /v RemotePath 2^>nul') do (
                if /I "%%H"=="RemotePath" (
                    if not "%%J"=="" (
                        >>"!MAPPED_DRIVES_FILE!" echo %%L: %%J
                        Set "MAPPED_DRIVES_EXPORTED=1"
                    )
                )
            )
        )
    )
    if "!MAPPED_DRIVES_EXPORTED!"=="1" (
        ECHO Mapped drive assignments exported to !MAPPED_DRIVES_FILE!
    ) else (
        if exist "!MAPPED_DRIVES_FILE!" del "!MAPPED_DRIVES_FILE!" >nul 2>&1
        ECHO No mapped drive RemotePath values found for !TARGET_USER_ID!.
    )
)
Set "MAPPED_DRIVES_FILE="
EXIT /B


:ExportOpenNotebooks
reg export !TEMP_HIVE_ROOT!\Software\Microsoft\Office\16.0\OneNote\OpenNoteBooks "C:\MOVEME\opennotebooks.txt" /y >nul 2>&1
if errorlevel 1 (
    ECHO OneNote Open Notebook registry key not found for !TARGET_USER_ID! or export failed.
) else (
    Set "OPEN_NOTEBOOKS_EXPORTED=1"
    ECHO OneNote open notebooks exported to C:\MOVEME\opennotebooks.txt
)
EXIT /B


:EOffice
if exist %office% 2> nul (
    mkdir %mlocal%\Microsoft\Office
    xcopy "%TARGET_LOCALAPPDATA%\Microsoft\Office\*.officeUI" %mlocal%\Microsoft\Office
) else (
    CLS
    color 40
    @ECHO.
    @ECHO.
    ECHO No Quick access configuration Found^^! If you expected files here, then verify manually.
    @ECHO.
    @ECHO.
color 07
)
GOTO ETeams



:ETeams
if exist %teams% 2> nul (
    mkdir %mroaming%\Microsoft\teams
    robocopy %teams% %mroaming%\Microsoft\teams /s /z /v /mt /XF "~$*" /log+:C:\MOVEME\robocopyexport.log /tee
) else (
    CLS
    color 40
    @ECHO.
    @ECHO.
    ECHO No Teams Backgrounds Folder Not Found^^! If you expected files here, then verify manually.
    @ECHO.
    @ECHO.
Pause
color 07
)
GOTO ESignature



:ESignature
if exist %sig% 2> nul (
    mkdir %mroaming%\Microsoft\Signatures
    robocopy %sig% %mroaming%\Microsoft\Signatures /s /z /v /mt /XF "~$*" /log+:C:\MOVEME\robocopyexport.log /tee
) else (
    CLS
    color 40
    @ECHO.
    @ECHO.
    ECHO No Email Signature Folder Not Found^^! If you expected files here, then verify manually.
    @ECHO.
    @ECHO.
Pause
color 07
)
GOTO EStickyNote



:EStickyNote
if exist %sticky_notes% 2> nul (
    mkdir %mlocal%\sticky_notes\LocalState
    robocopy %sticky_notes%  "%mlocal%\sticky_notes\LocalState" /s /z /v /mt /XF "~$*" /log+:C:\MOVEME\robocopyexport.log /tee plum*
) else (
    CLS
    color 40
    @ECHO.
    @ECHO.
    ECHO Sticky Notes Folder Not Found^^! If you expected files here, then verify manually.
    @ECHO.
    @ECHO.
Pause
color 07
)
GOTO EDocuments



:EDocuments
if exist %documents% 2> nul (
    mkdir %moveme%\docs
    robocopy %documents% %moveme%\docs /s /z /v /mt /XJ /XF "~$*" /R:1 /W:5 /log+:C:\MOVEME\robocopyexport.log /tee
) else (
    CLS
    color 40
    @ECHO.
    @ECHO.
    ECHO Documents Folder Not Found^^! If you expected files here, then verify manually.
    @ECHO.
    @ECHO.
Pause
color 07
)
GOTO EPictures



:EPictures
if exist %pictures% 2> nul (
    mkdir %moveme%\pics
    robocopy %pictures% %moveme%\pics /s /z /v /mt /XJ /XF "~$*" /R:1 /W:5 /log+:C:\MOVEME\robocopyexport.log /tee
) else (
    CLS
    color 40
    @ECHO.
    @ECHO.
    ECHO Pictures Folder Not Found^^! If you expected files here, then verify manually.
    @ECHO.
    @ECHO.    
Pause
color 07
)
GOTO EDesktop



:EDesktop
if exist %desktop% 2> nul (
    mkdir %moveme%\desktop
    robocopy %desktop% %moveme%\desktop /s /z /v /mt /xf "~$*" /R:1 /W:5 /log+:C:\MOVEME\robocopyexport.log /tee
) else (
    CLS
    color 40
    @ECHO.
    @ECHO.
    ECHO Desktop Folder Not Found^^! If you expected files here, then verify manually.
    @ECHO.
    @ECHO. 
Pause
color 07
)
GOTO EEdge



:EEdge
if exist %edge% 2> nul (
    mkdir %mlocal%Edge
    robocopy %edge% "%mlocal%Edge" Bookmarks* /s /z /v /mt /XF "~$*" /log+:C:\MOVEME\robocopyexport.log /tee
) else (
    CLS
    color 40
    @ECHO.
    @ECHO.
    ECHO Edge Bookmarks Folder Not Found^^!  If you expected files here, then verify manually.
    @ECHO.
    @ECHO.
Pause
color 07
)
GOTO EChrome




:EChrome
if exist %chrome% 2> nul (
    mkdir %mlocal%Chrome
    robocopy %chrome% "%mlocal%Chrome" Bookmarks* /s /z /v /mt /XF "~$*" /log+:C:\MOVEME\robocopyexport.log /tee
) else (
    CLS
    color 40
    @ECHO.
    @ECHO.
    ECHO Chrome Bookmarks Folder Not Found^^!  If you expected files here, then verify manually.
    @ECHO.
    @ECHO.
Pause
color 07
)
GOTO EQaccess


:EQaccess
if exist %qAccess% 2> nul (
    mkdir %mroaming%\quickpins
    robocopy %qAccess% "%mroaming%\quickpins" /s /z /v /mt /XF "~$*" /log+:C:\MOVEME\robocopyexport.log /tee
) else (
    CLS
    color 40
    @ECHO.
    @ECHO.
    ECHO Quick Access Pins Folder Not Found^^! If you expected files here, then verify manually.
    @ECHO.
    @ECHO.
Pause
color 07
)
GOTO Esnagitchoice


:Esnagitchoice
REM - Do you want to export snagit? 
CHOICE /C YN /T 30 /D Y /M "Do you want to export Snagit Snap shots? This exports the last 180 days by default."
If ERRORLEVEL 2 GOTO Conenote
GOTO Esnagit

:Esnagit
if exist %snagit% 2> nul ( 
    mkdir %mlocal%\datastore
    robocopy %snagit% %mlocal%\datastore ^
    /s /z /v /mt /MAXAGE:180 /XF "~$*" ^
    /log+:C:\MOVEME\robocopyexport.log /tee
) else (
    CLS
    color 40
    @ECHO.
    @ECHO.
    ECHO Snagit Folder Not Found^^! If you expected files here, then verify manually.
    @ECHO.
    @ECHO.
Pause
color 07
)
GOTO Conenote


:Conenote
if "!OPEN_NOTEBOOKS_EXPORTED!"=="1" (
    ECHO OneNote open notebooks already exported to C:\MOVEME\opennotebooks.txt
) else (
    ECHO OneNote open notebooks were not exported. Verify manually if required.
)
GOTO ESQLDevloper

:ESQLDevloper
if exist C:\SQLDevloper 2> nul ( 
    mkdir %mroaming%\SQLDevloper
    robocopy "%TARGET_APPDATA%\SQL Devloper" %mroaming%\SQLDevloper /s /z /v /mt /XF "~$*" /log+:C:\MOVEME\robocopyexport.log /tee
) else (
    CLS
    color 40
    @ECHO.
    @ECHO.
    ECHO SQL Developer Folder Not Found^^! If you expected files here, then verify manually.
    @ECHO.
    @ECHO.
Pause
color 07
GOTO Quit
)

robocopy C:\SQLDevloper C:\MOVEME\SQLDevloper /s /z /v /mt /XF "~$*" /log:+C:\MOVEME\robocopyimport.log
GOTO Quit




:ShouldIncludeProfile
Set "PROFILE_INCLUDE=0"
Set "PROFILE_CANDIDATE=%~1"
IF NOT DEFINED PROFILE_CANDIDATE EXIT /B
CALL :IsExcludedProfile "%PROFILE_CANDIDATE%"
IF "%PROFILE_EXCLUDED%"=="1" EXIT /B
Set "PROFILE_INCLUDE=1"
EXIT /B

:IsExcludedProfile
Set "PROFILE_EXCLUDED=0"
Set "PROFILE_TEST=%~1"
IF NOT DEFINED PROFILE_TEST EXIT /B
for %%E in ("Default" "Default User" "Public" "All Users" "DefaultAppPool" "WDAGUtilityAccount" "Administrator" "defaultuser0" "systemprofile") do (
    if /I "%PROFILE_TEST%"=="%%~E" (
        Set "PROFILE_EXCLUDED=1"
    )
)
IF "%PROFILE_EXCLUDED%"=="1" EXIT /B
Set "PROFILE_PREFIX=%PROFILE_TEST:~0,2%"
IF /I "%PROFILE_PREFIX%"=="A_" (
    Set "PROFILE_EXCLUDED=1"
)
EXIT /B


:QQuit
EXIT

:Quit
ENDLOCAL
CLS
@ECHO.
@ECHO.
@ECHO.
@ECHO.
ECHO All files have been transfered any OneNote notebooks, mapped network drives, and/or shared mailboxes will need recreated manually. 
@ECHO.
@ECHO.
Pause
CLS
color 0
EXIT
