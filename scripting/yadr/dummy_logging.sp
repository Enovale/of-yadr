#pragma newdecls required
#pragma semicolon 1

#define LOG4SP_NAME "log4sp"

void LoadDummyLoggingNatives()
{
    if (LibraryExists(LOG4SP_NAME))
    {
        return;
    }

    LogImpl(LOG4SP_NAME... " was not loaded! Using dummy logging...", false, "WARNING");
    CreateNative("LogLevelToName", DummyNative);
    CreateNative("LogLevelToShortName", DummyNative);
    CreateNative("NameToLogLevel", DummyNative);

    CreateNative("Logger.Logger", DummyNative);
    CreateNative("Logger.CreateLoggerWith", DummyNative);
    CreateNative("Logger.CreateLoggerWithEx", DummyNative);
    CreateNative("Logger.Get", DummyNative);
    CreateNative("Logger.ApplyAll", DummyNative);
    CreateNative("Logger.GetName", DummyNative);
    CreateNative("Logger.GetNameLength", DummyNative);
    CreateNative("Logger.GetLevel", DummyNative);
    CreateNative("Logger.SetLevel", DummyNative);
    CreateNative("Logger.SetPattern", DummyNative);
    CreateNative("Logger.ShouldLog", DummyNative);
    CreateNative("Logger.Log", MessageLog);
    CreateNative("Logger.LogEx", MessageLog);
    CreateNative("Logger.LogAmxTpl", DummyNative);
    CreateNative("Logger.LogSrc", DummyNative);
    CreateNative("Logger.LogSrcEx", DummyNative);
    CreateNative("Logger.LogSrcAmxTpl", DummyNative);
    CreateNative("Logger.LogLoc", DummyNative);
    CreateNative("Logger.LogLocEx", DummyNative);
    CreateNative("Logger.LogLocAmxTpl", DummyNative);
    CreateNative("Logger.LogStackTrace", DummyNative);
    CreateNative("Logger.LogStackTraceEx", DummyNative);
    CreateNative("Logger.LogStackTraceAmxTpl", DummyNative);
    CreateNative("Logger.ThrowError", DummyNative);
    CreateNative("Logger.ThrowErrorEx", DummyNative);
    CreateNative("Logger.ThrowErrorAmxTpl", DummyNative);
    CreateNative("Logger.Trace", TraceLog);
    CreateNative("Logger.TraceEx", TraceLog);
    CreateNative("Logger.TraceAmxTpl", DummyNative);
    CreateNative("Logger.Debug", DebugLog);
    CreateNative("Logger.DebugEx", DebugLog);
    CreateNative("Logger.DebugAmxTpl", DummyNative);
    CreateNative("Logger.Info", InfoLog);
    CreateNative("Logger.InfoEx", InfoLog);
    CreateNative("Logger.InfoAmxTpl", DummyNative);
    CreateNative("Logger.Warn", WarnLog);
    CreateNative("Logger.WarnEx", WarnLog);
    CreateNative("Logger.WarnAmxTpl", DummyNative);
    CreateNative("Logger.Error", ErrorLog);
    CreateNative("Logger.ErrorEx", ErrorLog);
    CreateNative("Logger.ErrorAmxTpl", DummyNative);
    CreateNative("Logger.Fatal", FatalLog);
    CreateNative("Logger.FatalEx", FatalLog);
    CreateNative("Logger.FatalAmxTpl", DummyNative);
    CreateNative("Logger.Flush", DummyNative);
    CreateNative("Logger.GetFlushLevel", DummyNative);
    CreateNative("Logger.FlushOn", DummyNative);
    CreateNative("Logger.AddSink", DummyNative);
    CreateNative("Logger.AddSinkEx", DummyNative);
    CreateNative("Logger.DropSink", DummyNative);
    CreateNative("Logger.SetErrorHandler", DummyNative);

    CreateNative("BasicFileSink.BasicFileSink", DummyNative);
    CreateNative("BasicFileSink.GetFilename", DummyNative);
    CreateNative("BasicFileSink.Truncate", DummyNative);
    CreateNative("BasicFileSink.CreateLogger", DummyNative);

    CreateNative("CallbackSink.CallbackSink", DummyNative);
    CreateNative("CallbackSink.SetLogCallback", DummyNative);
    CreateNative("CallbackSink.SetLogPostCallback", DummyNative);
    CreateNative("CallbackSink.SetFlushCallback", DummyNative);
    CreateNative("CallbackSink.CreateLogger", DummyNative);

    CreateNative("DailyFileSink.DailyFileSink", DummyNative);
    CreateNative("DailyFileSink.GetFilename", DummyNative);
    CreateNative("DailyFileSink.CreateLogger", DummyNative);

    CreateNative("RingBufferSink.RingBufferSink", DummyNative);
    CreateNative("RingBufferSink.Drain", DummyNative);
    CreateNative("RingBufferSink.DrainFormatted", DummyNative);
    CreateNative("RingBufferSink.CreateLogger", DummyNative);

    CreateNative("RotatingFileSink.RotatingFileSink", DummyNative);
    CreateNative("RotatingFileSink.GetFilename", DummyNative);
    CreateNative("RotatingFileSink.RotateNow", DummyNative);
    CreateNative("RotatingFileSink.CalcFilename", DummyNative);
    CreateNative("RotatingFileSink.CreateLogger", DummyNative);

    CreateNative("ServerConsoleSink.ServerConsoleSink", DummyNative);
    CreateNative("ServerConsoleSink.CreateLogger", DummyNative);

    CreateNative("Sink.GetLevel", DummyNative);
    CreateNative("Sink.SetLevel", DummyNative);
    CreateNative("Sink.SetPattern", DummyNative);
    CreateNative("Sink.ShouldLog", DummyNative);
    CreateNative("Sink.Log", DummyNative);
    CreateNative("Sink.ToPattern", DummyNative);
    CreateNative("Sink.Flush", DummyNative);
}

int MessageLog(Handle plugin, int numParams)
{
    LogWrapper(false);
    return 1;
}

int TraceLog(Handle plugin, int numParams)
{
    LogWrapper(false, "trace");
    return 1;
}

int DebugLog(Handle plugin, int numParams)
{
    LogWrapper(false, "debug");
    return 1;
}

int InfoLog(Handle plugin, int numParams)
{
    LogWrapper(false, "info");
    return 1;
}

int WarnLog(Handle plugin, int numParams)
{
    LogWrapper(false, "warn");
    return 1;
}

int ErrorLog(Handle plugin, int numParams)
{
    LogWrapper(true, "ERROR");
    return 1;
}

int FatalLog(Handle plugin, int numParams)
{
    LogWrapper(true, "FATAL");
    return 1;
}

void LogWrapper(bool error, char[] logLevel = "")
{
    char buffer[MAX_BUFFER_LENGTH];
    int  written;

    FormatNativeString(0,              /* Use an output buffer */
                       2,              /* Format param */
                       3,              /* Format argument #1 */
                       sizeof(buffer), /* Size of output buffer */
                       written,        /* Store # of written bytes */
                       buffer          /* Use our buffer */
    );

    LogImpl(buffer, error, logLevel);
}

void LogImpl(char[] str, bool error, char[] logLevel = "")
{
    char format[128];
    format = StrEqual(logLevel, "") ? "%s%s" : (error ? "%s: %s" : "[%s] %s");
    error ? LogError(format, logLevel, str) : LogMessage(format, logLevel, str);
}

int DummyNative(Handle plugin, int numParams)
{
    // Stub
    return 1;
}