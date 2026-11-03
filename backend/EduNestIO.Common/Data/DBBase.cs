namespace EduNestIO.Common.Data;

/// <summary>
/// Base class for all data-access (DA) classes. Original substitute for the
/// reference project's DBBase, preserving the shape DA code relies on:
///   - a <see cref="DbMaster"/> owning the connection,
///   - construction with a connection string,
///   - DA classes calling DbMaster.Connect()/CheckError() and the factory calling
///     Disconnect() via ReleaseDBObject.
/// </summary>
public abstract class DBBase
{
    protected DBBase(string connectionString)
    {
        ConnectionString = string.IsNullOrWhiteSpace(connectionString)
            ? AppConfig.DefaultConnectionString
            : connectionString;
        DbMaster = new DbMaster(ConnectionString);
    }

    protected string ConnectionString { get; }

    /// <summary>Connection owner used by DA methods: DbMaster.Connect() / .Connection.</summary>
    public DbMaster DbMaster { get; set; }
}
