using System.Net.Http.Headers;
using System.Net.Http.Json;
using EduNestIO.Common.Security;
using EduNestIO.WebServices.Business;
using EduNestIO.WebServices.RestAPI;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Newtonsoft.Json.Linq;

namespace EduNestIO.Tests;

/// <summary>
/// Spins up the real API against a real PostgreSQL. This architecture calls
/// PostgreSQL stored functions directly (no ORM), so there is no in-memory
/// substitute: a live database is required. The connection string is taken from the
/// EDUNESTIO_TEST_DB environment variable. When it is not set, the DB-backed tests
/// SKIP (see DbAvailable) rather than fail, so the suite stays green in environments
/// without a database while still running fully where one is provided.
///
/// The test database must have the /database scripts applied (schema + functions +
/// reference seed). The fixture seeds demo users itself via DevSeedBL.
/// </summary>
public sealed class IntegrationFixture : IDisposable
{
    public const string DemoPassword = "EduNestTest!2026";
    public static readonly string? TestDb = Environment.GetEnvironmentVariable("EDUNESTIO_TEST_DB");
    public static bool DbAvailable => !string.IsNullOrWhiteSpace(TestDb);

    public WebApplicationFactory<Program>? Factory { get; }

    public IntegrationFixture()
    {
        if (!DbAvailable)
        {
            return;
        }

        // Point the app at the test DB + enable dev seeding with a known password.
        Environment.SetEnvironmentVariable("ASPNETCORE_ENVIRONMENT", "Development");
        Environment.SetEnvironmentVariable("ConnectionStrings__Default", TestDb);
        Environment.SetEnvironmentVariable("Seed__Enabled", "true");
        Environment.SetEnvironmentVariable("Seed__DemoUserPassword", DemoPassword);

        Factory = new WebApplicationFactory<Program>()
            .WithWebHostBuilder(b => b.UseEnvironment("Development"));

        // Ensure seeding ran (the app seeds on startup; force host build + a seed call).
        _ = Factory.Server;
        try { new DevSeedBL().SeedDemoUsers(DemoPassword); } catch { /* app may have already seeded */ }
    }

    /// <summary>Logs in through the real HTTP endpoint and returns a token-bearing client.</summary>
    public async Task<HttpClient> LoginAsync(string username)
    {
        var client = Factory!.CreateClient();
        var resp = await client.PostAsJsonAsync("/api/auth/login", new { username, password = DemoPassword });
        resp.EnsureSuccessStatusCode();
        var body = JObject.Parse(await resp.Content.ReadAsStringAsync());
        var token = body["data"]!["token"]!.ToString();
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", token);
        return client;
    }

    public void Dispose() => Factory?.Dispose();
}

[CollectionDefinition("integration")]
public sealed class IntegrationCollection : ICollectionFixture<IntegrationFixture> { }
