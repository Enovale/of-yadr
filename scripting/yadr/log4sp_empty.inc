// Same log4sp.inc
#if defined _log4sp_included
  #error Cannot include both <log4sp> and "log4sp_empty.inc" at the same time
#endif

#pragma newdecls required
#pragma semicolon 1

/**
 * Rewrote all log4sp natives with pure sourcepawn, most of them are empty, and
 * use SM-Logging to simply logging log messages to ensure minimum availability.
 *
 * For logger logging operations:
 *      Log messages below the Error level are instead with SM-LogMessage.
 *      Log messages higher the Error level are instead with SM-LogError.
 *
 * For logger special logging operations:
 *      Logger::LogStackTrace uses SM-LogStackTrace instead.
 *      Logger::ThrowError uses SM-ThrowError instead.
 *
 * Does not support modifying the log filter level at runtime.
 * Which log messages can be logged is determined at compile time.
 * You can change it by modifying macro: __COMPILER_LOG_LEVEL
 * Logger.ThorwError will always execute regardless of the log level.
 *
 * Since most method bodies are empty, you can pass "-w 203" to spcomp when
 * compiling the plugin to suppress warnings.
 */

#if !defined __COMPILER_LOG_LEVEL
#define __COMPILER_LOG_LEVEL            LOG4SP_LEVEL_INFO
#endif

// Common
#if defined _log4sp_common_included
  #error Cannot include both <log4sp/common> and "log4sp_empty.inc" at the same time
#endif
#define LOG4SP_LEVEL_TRACE              0
#define LOG4SP_LEVEL_DEBUG              1
#define LOG4SP_LEVEL_INFO               2
#define LOG4SP_LEVEL_WARN               3
#define LOG4SP_LEVEL_ERROR              4
#define LOG4SP_LEVEL_FATAL              5
#define LOG4SP_LEVEL_OFF                6
#define LOG4SP_LEVEL_NAME_TRACE         "trace"
#define LOG4SP_LEVEL_NAME_DEBUG         "debug"
#define LOG4SP_LEVEL_NAME_INFO          "info"
#define LOG4SP_LEVEL_NAME_WARN          "warn"
#define LOG4SP_LEVEL_NAME_ERROR         "error"
#define LOG4SP_LEVEL_NAME_FATAL         "fatal"
#define LOG4SP_LEVEL_NAME_OFF           "off"
#define LOG4SP_LEVEL_SHORT_NAME_TRACE   "T"
#define LOG4SP_LEVEL_SHORT_NAME_DEBUG   "D"
#define LOG4SP_LEVEL_SHORT_NAME_INFO    "I"
#define LOG4SP_LEVEL_SHORT_NAME_WARN    "W"
#define LOG4SP_LEVEL_SHORT_NAME_ERROR   "E"
#define LOG4SP_LEVEL_SHORT_NAME_FATAL   "F"
#define LOG4SP_LEVEL_SHORT_NAME_OFF     "O"
#define LOG4SP_GLOBAL_LOGGER_NAME       "log4sp"

enum LogLevel {
  LogLevel_Trace = LOG4SP_LEVEL_TRACE,
  LogLevel_Debug = LOG4SP_LEVEL_DEBUG,
  LogLevel_Info  = LOG4SP_LEVEL_INFO,
  LogLevel_Warn  = LOG4SP_LEVEL_WARN,
  LogLevel_Error = LOG4SP_LEVEL_ERROR,
  LogLevel_Fatal = LOG4SP_LEVEL_FATAL,
  LogLevel_Off   = LOG4SP_LEVEL_OFF,
  LogLevel_Total
}
enum PatternTimeType {
  PatternTimeType_Local,
  PatternTimeType_Utc
};
enum struct SourceLoc {
  char filename[PLATFORM_MAX_PATH];
  int line;
  char funcname[PLATFORM_MAX_PATH];
  bool IsEmpty() {
    return !this.filename[0] || this.line <= 0 || !this.funcname[0];
  }
}

stock int LogLevelToName(char[] buffer, int maxlen, LogLevel lvl) {
  switch(lvl) {
    case LogLevel_Trace : return FormatEx(buffer, maxlen, LOG4SP_LEVEL_NAME_TRACE);
    case LogLevel_Debug : return FormatEx(buffer, maxlen, LOG4SP_LEVEL_NAME_DEBUG);
    case LogLevel_Info  : return FormatEx(buffer, maxlen, LOG4SP_LEVEL_NAME_INFO);
    case LogLevel_Warn  : return FormatEx(buffer, maxlen, LOG4SP_LEVEL_NAME_WARN);
    case LogLevel_Error : return FormatEx(buffer, maxlen, LOG4SP_LEVEL_NAME_ERROR);
    case LogLevel_Fatal : return FormatEx(buffer, maxlen, LOG4SP_LEVEL_NAME_FATAL);
  }
  return FormatEx(buffer, maxlen, LOG4SP_LEVEL_NAME_OFF);
}

stock int LogLevelToShortName(char[] buffer, int maxlen, LogLevel lvl) {
  switch(lvl) {
    case LogLevel_Trace : return FormatEx(buffer, maxlen, LOG4SP_LEVEL_SHORT_NAME_TRACE);
    case LogLevel_Debug : return FormatEx(buffer, maxlen, LOG4SP_LEVEL_SHORT_NAME_DEBUG);
    case LogLevel_Info  : return FormatEx(buffer, maxlen, LOG4SP_LEVEL_SHORT_NAME_INFO);
    case LogLevel_Warn  : return FormatEx(buffer, maxlen, LOG4SP_LEVEL_SHORT_NAME_WARN);
    case LogLevel_Error : return FormatEx(buffer, maxlen, LOG4SP_LEVEL_SHORT_NAME_ERROR);
    case LogLevel_Fatal : return FormatEx(buffer, maxlen, LOG4SP_LEVEL_SHORT_NAME_FATAL);
  }
  return FormatEx(buffer, maxlen, LOG4SP_LEVEL_SHORT_NAME_OFF);
}

stock LogLevel NameToLogLevel(const char[] name) {
  if (StrEqual(name, LOG4SP_LEVEL_NAME_TRACE)) return LogLevel_Trace;
  if (StrEqual(name, LOG4SP_LEVEL_NAME_DEBUG)) return LogLevel_Debug;
  if (StrEqual(name, LOG4SP_LEVEL_NAME_INFO))  return LogLevel_Info;
  if (StrEqual(name, LOG4SP_LEVEL_NAME_WARN))  return LogLevel_Warn;
  if (StrEqual(name, LOG4SP_LEVEL_NAME_ERROR)) return LogLevel_Error;
  if (StrEqual(name, "err"))                   return LogLevel_Error;
  if (StrEqual(name, LOG4SP_LEVEL_NAME_FATAL)) return LogLevel_Fatal;
  return LogLevel_Off;
}

// Logger
#if defined _log4sp_logger_included
  #error Cannot include both <log4sp/logger> and "log4sp_empty.inc" at the same time
#endif
typeset LoggerErrorHandler {
  function void (const char[] msg);
  function void (const char[] msg, const char[] name);
  function void (const char[] msg, const char[] name, const char[] file, int line, const char[] func);
};
typeset LoggerApplyAllCallback {
  function void (Logger logger);
  function void (Logger logger, any data);
};

// LogMessage and LogError can handle 1024 characters.
// LogStackTrace and ThrowError can handle 512 characters.
static char __gLoggerInnerBuffer[1024];

methodmap Logger < Handle {
  public Logger(const char[] name) {
    return null;
  }
  public static Logger CreateLoggerWith(const char[] name, Sink[] sinks, int numSinks) {
    return null;
  }
  public static Logger CreateLoggerWithEx(const char[] name, Sink[] sinks, int numSinks) {
    return null;
  }
  public static Logger Get(const char[] name) {
    return null;
  }
  public static void ApplyAll(LoggerApplyAllCallback callback, any data = 0) {}
  public int GetName(char[] buffer, int maxlen) {
    return 0;
  }
  public int GetNameLength() {
    return 0;
  }
  public LogLevel GetLevel() {
    return view_as<LogLevel>(__COMPILER_LOG_LEVEL);
  }
  public void SetLevel(LogLevel lvl) {}
  public void SetPattern(const char[] pattern, PatternTimeType type = PatternTimeType_Local) {}
  public bool ShouldLog(LogLevel lvl) {
    return lvl >= this.GetLevel();
  }
  public void Log(LogLevel lvl, const char[] msg) {
      __LoggerInner_Log(lvl, msg);
  }
  public void LogEx(LogLevel lvl, const char[] fmt, any ...) {
    VFormat(__gLoggerInnerBuffer, sizeof(__gLoggerInnerBuffer), fmt, 4);
    __LoggerInner_Log(lvl, __gLoggerInnerBuffer);
  }
  public void LogAmxTpl(LogLevel lvl, const char[] fmt, any ...) {
    VFormat(__gLoggerInnerBuffer, sizeof(__gLoggerInnerBuffer), fmt, 4);
    __LoggerInner_Log(lvl, __gLoggerInnerBuffer);
  }
  public void LogSrc(LogLevel lvl, const char[] msg) {
    __LoggerInner_LogSrc(lvl, msg);
  }
  public void LogSrcEx(LogLevel lvl, const char[] fmt, any ...) {
    VFormat(__gLoggerInnerBuffer, sizeof(__gLoggerInnerBuffer), fmt, 4);
    __LoggerInner_LogSrc(lvl, __gLoggerInnerBuffer);
  }
  public void LogSrcAmxTpl(LogLevel lvl, const char[] fmt, any ...) {
    VFormat(__gLoggerInnerBuffer, sizeof(__gLoggerInnerBuffer), fmt, 4);
    __LoggerInner_LogSrc(lvl, __gLoggerInnerBuffer);
  }
  public void LogLoc(const char[] file, int line, const char[] func, LogLevel lvl, const char[] msg) {
    __LoggerInner_LogLoc(file, line, lvl, msg);
  }
  public void LogLocEx(const char[] file, int line, const char[] func, LogLevel lvl, const char[] fmt, any ...) {
    VFormat(__gLoggerInnerBuffer, sizeof(__gLoggerInnerBuffer), fmt, 7);
    __LoggerInner_LogLoc(file, line, lvl, __gLoggerInnerBuffer);
  }
  public void LogLocAmxTpl(const char[] file, int line, const char[] func, LogLevel lvl, const char[] fmt, any ...) {
    VFormat(__gLoggerInnerBuffer, sizeof(__gLoggerInnerBuffer), fmt, 7);
    __LoggerInner_LogLoc(file, line, lvl, __gLoggerInnerBuffer);
  }
  public void LogStackTrace(LogLevel lvl, const char[] msg) {
    __LoggerInner_LogStackTrace(lvl, msg);
  }
  public void LogStackTraceEx(LogLevel lvl, const char[] fmt, any ...) {
    VFormat(__gLoggerInnerBuffer, sizeof(__gLoggerInnerBuffer), fmt, 4);
    __LoggerInner_LogStackTrace(lvl, __gLoggerInnerBuffer);
  }
  public void LogStackTraceAmxTpl(LogLevel lvl, const char[] fmt, any ...) {
    VFormat(__gLoggerInnerBuffer, sizeof(__gLoggerInnerBuffer), fmt, 4);
    __LoggerInner_LogStackTrace(lvl, __gLoggerInnerBuffer);
  }
  public void ThrowError(LogLevel lvl, const char[] msg) {
    __LoggerInner_ThrowError(lvl, msg);
  }
  public void ThrowErrorEx(LogLevel lvl, const char[] fmt, any ...) {
    VFormat(__gLoggerInnerBuffer, sizeof(__gLoggerInnerBuffer), fmt, 4);
    __LoggerInner_ThrowError(lvl, __gLoggerInnerBuffer);
  }
  public void ThrowErrorAmxTpl(LogLevel lvl, const char[] fmt, any ...) {
    VFormat(__gLoggerInnerBuffer, sizeof(__gLoggerInnerBuffer), fmt, 4);
    __LoggerInner_ThrowError(lvl, __gLoggerInnerBuffer);
  }
  public void Trace(const char[] msg) {
    __LoggerInner_Log(LogLevel_Trace, msg);
  }
  public void TraceEx(const char[] fmt, any ...) {
    VFormat(__gLoggerInnerBuffer, sizeof(__gLoggerInnerBuffer), fmt, 3);
    __LoggerInner_Log(LogLevel_Trace, __gLoggerInnerBuffer);
  }
  public void TraceAmxTpl(const char[] fmt, any ...) {
    VFormat(__gLoggerInnerBuffer, sizeof(__gLoggerInnerBuffer), fmt, 3);
    __LoggerInner_Log(LogLevel_Trace, __gLoggerInnerBuffer);
  }
  public void Debug(const char[] msg) {
    __LoggerInner_Log(LogLevel_Debug, msg);
  }
  public void DebugEx(const char[] fmt, any ...) {
    VFormat(__gLoggerInnerBuffer, sizeof(__gLoggerInnerBuffer), fmt, 3);
    __LoggerInner_Log(LogLevel_Debug, __gLoggerInnerBuffer);
  }
  public void DebugAmxTpl(const char[] fmt, any ...) {
    VFormat(__gLoggerInnerBuffer, sizeof(__gLoggerInnerBuffer), fmt, 3);
    __LoggerInner_Log(LogLevel_Debug, __gLoggerInnerBuffer);
  }
  public void Info(const char[] msg) {
    __LoggerInner_Log(LogLevel_Info, msg);
  }
  public void InfoEx(const char[] fmt, any ...) {
    VFormat(__gLoggerInnerBuffer, sizeof(__gLoggerInnerBuffer), fmt, 3);
    __LoggerInner_Log(LogLevel_Info, __gLoggerInnerBuffer);
  }
  public void InfoAmxTpl(const char[] fmt, any ...) {
    VFormat(__gLoggerInnerBuffer, sizeof(__gLoggerInnerBuffer), fmt, 3);
    __LoggerInner_Log(LogLevel_Info, __gLoggerInnerBuffer);
  }
  public void Warn(const char[] msg) {
    __LoggerInner_Log(LogLevel_Warn, msg);
  }
  public void WarnEx(const char[] fmt, any ...) {
    VFormat(__gLoggerInnerBuffer, sizeof(__gLoggerInnerBuffer), fmt, 3);
    __LoggerInner_Log(LogLevel_Warn, __gLoggerInnerBuffer);
  }
  public void WarnAmxTpl(const char[] fmt, any ...) {
    VFormat(__gLoggerInnerBuffer, sizeof(__gLoggerInnerBuffer), fmt, 3);
    __LoggerInner_Log(LogLevel_Warn, __gLoggerInnerBuffer);
  }
  public void Error(const char[] msg) {
    __LoggerInner_Log(LogLevel_Error, msg);
  }
  public void ErrorEx(const char[] fmt, any ...) {
    VFormat(__gLoggerInnerBuffer, sizeof(__gLoggerInnerBuffer), fmt, 3);
    __LoggerInner_Log(LogLevel_Error, __gLoggerInnerBuffer);
  }
  public void ErrorAmxTpl(const char[] fmt, any ...) {
    VFormat(__gLoggerInnerBuffer, sizeof(__gLoggerInnerBuffer), fmt, 3);
    __LoggerInner_Log(LogLevel_Error, __gLoggerInnerBuffer);
  }
  public void Fatal(const char[] msg) {
    __LoggerInner_Log(LogLevel_Fatal, msg);
  }
  public void FatalEx(const char[] fmt, any ...) {
    VFormat(__gLoggerInnerBuffer, sizeof(__gLoggerInnerBuffer), fmt, 3);
    __LoggerInner_Log(LogLevel_Fatal, __gLoggerInnerBuffer);
  }
  public void FatalAmxTpl(const char[] fmt, any ...) {
    VFormat(__gLoggerInnerBuffer, sizeof(__gLoggerInnerBuffer), fmt, 3);
    __LoggerInner_Log(LogLevel_Fatal, __gLoggerInnerBuffer);
  }
  public void Flush() {}
  public LogLevel GetFlushLevel() {
    return LogLevel_Off;
  }
  public void FlushOn(LogLevel lvl) {}
  public void AddSink(Sink sink) {}
  public void AddSinkEx(Sink sink) {}
  public void DropSink(Sink sink) {}
  public void SetErrorHandler(LoggerErrorHandler handler) {}
}

// Sink
#if defined _log4sp_sinks_sink_included
  #error Cannot include both <log4sp/logger> and "log4sp_empty.inc" at the same time
#endif
typedef SinkFileOpenPre = function void (const char[] filename);
typedef SinkFileClosePost = function void (const char[] filename);

methodmap Sink < Handle {
  public LogLevel GetLevel() {
    return view_as<LogLevel>(__COMPILER_LOG_LEVEL);
  }
  public void SetLevel(LogLevel lvl) {}
  public void SetPattern(const char[] pattern) {}
  public bool ShouldLog(LogLevel lvl) {
    return false;
  }
  public void Log(const char[] name, LogLevel lvl, const char[] msg, const char[] file = NULL_STRING, int line = 0, const char[] func = NULL_STRING, int logTime = -1) {}
  public int ToPattern(char[] buffer, int maxlen, const char[] name, LogLevel lvl, const char[] msg, const char[] file = NULL_STRING, int line = 0, const char[] func = NULL_STRING, int logTime = -1) {
    return 0;
  }
  public void Flush() {}
}

// BasicFileSink
#if defined _log4sp_sinks_basic_file_sink_included
  #error Cannot include both <log4sp/basic_file_sink> and "log4sp_empty.inc" at the same time
#endif
methodmap BasicFileSink < Sink {
  public BasicFileSink(const char[] file, bool truncate = false, SinkFileOpenPre openPre = INVALID_FUNCTION, SinkFileClosePost closePost = INVALID_FUNCTION) {
    return null;
  }
  public int GetFilename(char[] buffer, int maxlen) {
    return 0;
  }
  public int GetFilenameLength(char[] buffer, int maxlen) {
    return 0;
  }
  public void Truncate() {}
  public static Logger CreateLogger( const char[] name, const char[] file, bool truncate = false, SinkFileOpenPre onOpen = INVALID_FUNCTION, SinkFileClosePost onClose = INVALID_FUNCTION) {
    return null;
  }
}

// CallbackSink
#if defined _log4sp_sinks_callback_sink_included
  #error Cannot include both <log4sp/callback_sink> and "log4sp_empty.inc" at the same time
#endif
typeset CustomLogCallback {
  function void (const char[] name, LogLevel lvl, const char[] msg);
  function void (const char[] name, LogLevel lvl, const char[] msg, const char[] file, int line, const char[] func);
  function void (const char[] name, LogLevel lvl, const char[] msg, const char[] file, int line, const char[] func, int logTime);
}
typedef CustomLogPostCallback = function void (const char[] msg);
typedef CustomFlushCallback = function void ();

methodmap CallbackSink < Sink {
  public CallbackSink(CustomLogCallback logCallback = INVALID_FUNCTION, CustomLogPostCallback logPostCallback = INVALID_FUNCTION, CustomFlushCallback flushCallback = INVALID_FUNCTION) {
    return null;
  }
  public void SetLogCallback(CustomLogCallback logCallback) {}
  public void SetLogPostCallback(CustomLogPostCallback logPostCallback) {}
  public void SetFlushCallback(CustomFlushCallback flushCallback) {}
  public static Logger CreateLogger(const char[] name, CustomLogCallback logCallback = INVALID_FUNCTION, CustomLogPostCallback logPostCallback = INVALID_FUNCTION, CustomFlushCallback flushCallback = INVALID_FUNCTION) {
    return null;
  }
}

// ClientChatAllSink
#if defined _log4sp_sinks_client_chat_all_sink_included
  #error Cannot include both <log4sp/client_chat_all_sink> and "log4sp_empty.inc" at the same time
#endif
methodmap ClientChatAllSink < CallbackSink {
  public ClientChatAllSink() {
    return null;
  }
  public static Logger CreateLogger(const char[] name) {
    return null;
  }
}

// ClientConsoleAllSink
#if defined _log4sp_sinks_client_console_all_sink_included
  #error Cannot include both <log4sp/client_console_all_sink> and "log4sp_empty.inc" at the same time
#endif
methodmap ClientConsoleAllSink < CallbackSink {
  public ClientConsoleAllSink() {
    return null;
  }
  public static Logger CreateLogger(const char[] name) {
    return null;
  }
}

// DailyFileSink
#if defined _log4sp_sinks_daily_file_sink_included
  #error Cannot include both <log4sp/daily_file_sink> and "log4sp_empty.inc" at the same time
#endif
typeset DailyFileCalculator {
  function void (char[] filename, int maxlen, int sec);
}

methodmap DailyFileSink < Sink {
  public DailyFileSink(const char[] file, int hour = 0, int minute = 0, bool truncate = false, int maxFiles = 0, DailyFileCalculator calculator = INVALID_FUNCTION, SinkFileOpenPre openPre = INVALID_FUNCTION, SinkFileClosePost closePost = INVALID_FUNCTION) {
    return null;
  }
  public int GetFilename(char[] buffer, int maxlen) {
    return 0;
  }
  public int GetFilenameLength() {
    return 0;
  }
  public static Logger CreateLogger(const char[] name, const char[] file, int hour = 0, int minute = 0, bool truncate = false, int maxFiles = 0, DailyFileCalculator callback = INVALID_FUNCTION, SinkFileOpenPre openPre = INVALID_FUNCTION, SinkFileClosePost closePost = INVALID_FUNCTION) {
    return null;
  }
}

// RingBufferSink
#if defined _log4sp_sinks_ringbuffer_sink_included
  #error Cannot include both <log4sp/ringbuffer_sink> and "log4sp_empty.inc" at the same time
#endif
typeset DrainCallback {
  function void (const char[] name, LogLevel lvl, const char[] msg);
  function void (const char[] name, LogLevel lvl, const char[] msg, const char[] file, int line, const char[] func);
  function void (const char[] name, LogLevel lvl, const char[] msg, const char[] file, int line, const char[] func, int logTime);
  function void (const char[] name, LogLevel lvl, const char[] msg, const char[] file, int line, const char[] func, int logTime, any data);
}
typeset DrainFormattedCallback {
  function void (const char[] msg);
  function void (const char[] msg, any data);
}

methodmap RingBufferSink < Sink {
  public RingBufferSink(int amount) {
    return null;
  }
  public void Drain(DrainCallback callback, any data = 0) {}
  public void DrainFormatted(DrainFormattedCallback callback, any data = 0) {}

  #pragma deprecated This cannot be done using the RingbufferSink function.
  public static Logger CreateLogger(const char[] name, int amount) {
    return null;
  }
}

// RotatingFileSink
#if defined _log4sp_sinks_rotating_file_sink_included
  #error Cannot include both <log4sp/rotating_file_sink> and "log4sp_empty.inc" at the same time
#endif
methodmap RotatingFileSink < Sink {
  public RotatingFileSink(const char[] file, const int maxFileSize, const int maxFiles, bool rotateOnOpen = false, SinkFileOpenPre openPre = INVALID_FUNCTION, SinkFileClosePost closePost = INVALID_FUNCTION) {
    return null;
  }
  public int GetFilename(char[] buffer, int maxlen){
    return 0;
  }
  public int GetFilenameLength() {
    return 0;
  }
  public void RotateNow() {}
  public static int CalcFilename(char[] buffer, int maxlen, const char[] file, int index) {
    if (index == 0)
      return strlen(buffer);

    char filename[PLATFORM_MAX_PATH];
    strcopy(filename, sizeof(filename), file);
    int extIndex = FindCharInString(filename, '.', true);

    // no valid extension found
    if (extIndex <= 0 || extIndex == strlen(filename) - 1)
      return FormatEx(buffer, maxlen, "%s-%u", filename, index);

    // treat cases like "/etc/rc.d/somelogfile or "/abc/.hiddenfile"
    int folderIndex = FindCharInString(filename, '/', true);
    if (folderIndex == -1)
      folderIndex = FindCharInString(filename, '\\', true);
    if (folderIndex != -1 && folderIndex >= extIndex - 1)
      return FormatEx(buffer, maxlen, "%s-%u", filename, index);

    filename[extIndex] = '\0';
    return FormatEx(buffer, maxlen, "%s-%u.%s", filename, index, filename[extIndex + 1]);
  }
  public static Logger CreateLogger(const char[] name, const char[] file, int maxFileSize, int maxFiles, bool rotateOnOpen = false, SinkFileOpenPre openPre = INVALID_FUNCTION, SinkFileClosePost closePost = INVALID_FUNCTION) {
    return null;
  }
}

// ServerConsoleSink
#if defined _log4sp_sinks_server_console_sink_included
  #error Cannot include both <log4sp/server_console_sink> and "log4sp_empty.inc" at the same time
#endif
methodmap ServerConsoleSink < Sink {
  public ServerConsoleSink() {
    return null;
  }
  public static Logger CreateLogger(const char[] name) {
    return null;
  }
}


// Logger Inner
static void __LoggerInner_Log(LogLevel lvl, const char[] msg) {
  switch (lvl) {
#if __COMPILER_LOG_LEVEL <= LOG4SP_LEVEL_TRACE
    case LogLevel_Trace : LogMessage("["... LOG4SP_LEVEL_NAME_TRACE ..."] %s", msg);
#endif
#if __COMPILER_LOG_LEVEL <= LOG4SP_LEVEL_DEBUG
    case LogLevel_Debug : LogMessage("["... LOG4SP_LEVEL_NAME_DEBUG ..."] %s", msg);
#endif
#if __COMPILER_LOG_LEVEL <= LOG4SP_LEVEL_INFO
    case LogLevel_Info  : LogMessage("["... LOG4SP_LEVEL_NAME_INFO ..."] %s", msg);
#endif
#if __COMPILER_LOG_LEVEL <= LOG4SP_LEVEL_WARN
    case LogLevel_Warn  : LogMessage("["... LOG4SP_LEVEL_NAME_WARN ..."] %s", msg);
#endif
#if __COMPILER_LOG_LEVEL <= LOG4SP_LEVEL_ERROR
    case LogLevel_Error : LogError("["... LOG4SP_LEVEL_NAME_ERROR ..."] %s", msg);
#endif
#if __COMPILER_LOG_LEVEL <= LOG4SP_LEVEL_FATAL
    case LogLevel_Fatal : LogError("["... LOG4SP_LEVEL_NAME_FATAL ..."] %s", msg);
#endif
#if __COMPILER_LOG_LEVEL <= LOG4SP_LEVEL_OFF
    default             : LogError("["... LOG4SP_LEVEL_NAME_OFF ..."] %s", msg);
#endif
  }
}

static void __LoggerInner_LogSrc(LogLevel lvl, const char[] msg) {
  FrameIterator iter = new FrameIterator();
  iter.Next();  iter.Next();  iter.Next();

  char file[PLATFORM_MAX_PATH];
  iter.GetFilePath(file, sizeof(file));

  int line = iter.LineNumber;
  delete iter;

  __LoggerInner_LogLoc(file, line, lvl, msg);
}

static void __LoggerInner_LogLoc(const char[] file, int line, LogLevel lvl, const char[] msg) {
  int folderIndex = FindCharInString(file, '/', true);
  if (folderIndex == -1)
    folderIndex = FindCharInString(file, '\\', true);

  char message[1024];
  if (folderIndex == -1)
    FormatEx(message, sizeof(message), "[%s:%d] %s", file, line, msg);
  else
    FormatEx(message, sizeof(message), "[%s:%d] %s", file[folderIndex + 1], line, msg);

  __LoggerInner_Log(lvl, message);
}

static void __LoggerInner_LogStackTrace(LogLevel lvl, const char[] msg) {
  switch (lvl) {
#if __COMPILER_LOG_LEVEL <= LOG4SP_LEVEL_TRACE
    case LogLevel_Trace : LogStackTrace("["... LOG4SP_LEVEL_NAME_TRACE ..."] %s", msg);
#endif
#if __COMPILER_LOG_LEVEL <= LOG4SP_LEVEL_DEBUG
    case LogLevel_Debug : LogStackTrace("["... LOG4SP_LEVEL_NAME_DEBUG ..."] %s", msg);
#endif
#if __COMPILER_LOG_LEVEL <= LOG4SP_LEVEL_INFO
    case LogLevel_Info  : LogStackTrace("["... LOG4SP_LEVEL_NAME_INFO ..."] %s", msg);
#endif
#if __COMPILER_LOG_LEVEL <= LOG4SP_LEVEL_WARN
    case LogLevel_Warn  : LogStackTrace("["... LOG4SP_LEVEL_NAME_WARN ..."] %s", msg);
#endif
#if __COMPILER_LOG_LEVEL <= LOG4SP_LEVEL_ERROR
    case LogLevel_Error : LogStackTrace("["... LOG4SP_LEVEL_NAME_ERROR ..."] %s", msg);
#endif
#if __COMPILER_LOG_LEVEL <= LOG4SP_LEVEL_FATAL
    case LogLevel_Fatal : LogStackTrace("["... LOG4SP_LEVEL_NAME_FATAL ..."] %s", msg);
#endif
#if __COMPILER_LOG_LEVEL <= LOG4SP_LEVEL_OFF
    default             : LogStackTrace("["... LOG4SP_LEVEL_NAME_OFF ..."] %s", msg);
#endif
  }
}

static void __LoggerInner_ThrowError(LogLevel lvl, const char[] msg) {
  // In any case, an error should be thrown to ensure that the code is interrupted.
  switch (lvl) {
    case LogLevel_Trace : ThrowError("["... LOG4SP_LEVEL_NAME_TRACE ..."] %s", msg);
    case LogLevel_Debug : ThrowError("["... LOG4SP_LEVEL_NAME_DEBUG ..."] %s", msg);
    case LogLevel_Info  : ThrowError("["... LOG4SP_LEVEL_NAME_INFO ..."] %s", msg);
    case LogLevel_Warn  : ThrowError("["... LOG4SP_LEVEL_NAME_WARN ..."] %s", msg);
    case LogLevel_Error : ThrowError("["... LOG4SP_LEVEL_NAME_ERROR ..."] %s", msg);
    case LogLevel_Fatal : ThrowError("["... LOG4SP_LEVEL_NAME_FATAL ..."] %s", msg);
    default             : ThrowError("["... LOG4SP_LEVEL_NAME_OFF ..."] %s", msg);
  }
}
