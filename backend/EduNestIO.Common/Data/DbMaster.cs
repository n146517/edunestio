using EduNestIO.Common.Logging;
using Npgsql;

namespace EduNestIO.Common.Data;

/// <summary>
/// Owns a single PostgreSQL connection for a data-access operation. Original
/// substitute for the reference project's proprietary Beanbag.DatabasePool master
/// object, preserving the Connect()/Disconnect()/CheckError() surface used by DA
/// classes. Npgsql already provides an internal connection pool, so this type is a
/// thin, correct wrapper (open on Connect, return-to-pool on Disconnect).
/// </summary>
public sealed class DbMaster
{
    private readonly string _connectionString;

    public DbMaster(string connectionString)
    {
        _connectionString = connectionString;
    }

    public NpgsqlConnection? Connection { get; private set; }

    /// <summary>Opens the connection (drawn from Npgsql's pool) if not already open.</summary>
    public void Connect()
    {
        if (Connection is { State: System.Data.ConnectionState.Open })
        {
            return;
        }

        Connection = new NpgsqlConnection(_connectionString);
        Connection.Open();
    }

    /// <summary>Closes/returns the connection to the pool. Safe to call repeatedly.</summary>
    public void Disconnect()
    {
        try
        {
            if (Connection is not null)
            {
                Connection.Close();
                Connection.Dispose();
            }
        }
        finally
        {
            Connection = null;
        }
    }

    /// <summary>
    /// Inspects an exception and marks the connection unusable. Mirrors the reference
    /// CheckError hook so DA catch blocks can call it before rethrowing.
    /// </summary>
    public void CheckError(Exception ex)
    {
        LogWriter.WriteLog(new LogDTO
        {
            FunctionName = nameof(CheckError),
            ClassName = nameof(DbMaster),
            LogStringLevel = LoggingLevel.Exceptional,
            ExceptionString = ex.Message,
            StackTrace = ex.StackTrace,
            Message = "Database error"
        });

        // Drop the (possibly broken) connection so a fresh one is taken next time.
        try { Connection?.Dispose(); } catch { /* ignore */ }
        Connection = null;
    }
}
