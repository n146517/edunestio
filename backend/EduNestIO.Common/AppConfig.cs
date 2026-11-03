using Microsoft.Extensions.Configuration;

namespace EduNestIO.Common;

/// <summary>
/// Central configuration holder, equivalent in spirit to the reference project's
/// SystemParamsDTO/AppSettings. Loaded once at startup from config/appsettings.json
/// and environment variables. Holds NO secrets in source; values are supplied at
/// runtime via configuration/environment.
/// </summary>
public static class AppConfig
{
    public static string DefaultConnectionString { get; private set; } = string.Empty;
    public static string Url { get; private set; } = "https://localhost:7001";
    public static int DbPoolSize { get; private set; } = 20;

    /// <summary>Named connection strings (supports multi-DB/tenant routing later).</summary>
    public static IReadOnlyDictionary<string, string> DbConnections { get; private set; }
        = new Dictionary<string, string>();

    public static string LogDirectory { get; private set; } = Path.Combine(AppContext.BaseDirectory, "logs");

    public static void LoadParameters(IConfiguration configuration)
    {
        DefaultConnectionString =
            configuration.GetConnectionString("Default")
            ?? Environment.GetEnvironmentVariable("EDUNESTIO_DB_CONNECTION")
            ?? throw new InvalidOperationException(
                "No database connection string configured. Set ConnectionStrings:Default or EDUNESTIO_DB_CONNECTION.");

        Url = configuration["App:Url"] ?? Url;
        if (int.TryParse(configuration["App:DbPoolSize"], out var pool)) DbPoolSize = pool;
        LogDirectory = configuration["App:LogDirectory"] ?? LogDirectory;

        var conns = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
        {
            ["Default"] = DefaultConnectionString
        };
        foreach (var child in configuration.GetSection("ConnectionStrings").GetChildren())
        {
            if (!string.IsNullOrWhiteSpace(child.Value))
            {
                conns[child.Key] = child.Value;
            }
        }
        DbConnections = conns;
    }
}
