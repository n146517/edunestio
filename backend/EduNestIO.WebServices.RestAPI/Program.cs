namespace EduNestIO.WebServices.RestAPI;

/// <summary>
/// Host entry point. Uses the classic Startup split (ConfigureServices/Configure)
/// to match the reference project's hosting model.
/// </summary>
public partial class Program
{
    public static void Main(string[] args)
    {
        CreateHostBuilder(args).Build().Run();
    }

    public static IHostBuilder CreateHostBuilder(string[] args) =>
        Host.CreateDefaultBuilder(args)
            .ConfigureWebHostDefaults(webBuilder =>
            {
                webBuilder.UseStartup<Startup>();
            });
}

// Exposed so the integration test project (WebApplicationFactory) can reference the entry point.
public partial class Program { }
