using System.Net;
using System.Net.Http.Json;
using Newtonsoft.Json.Linq;

namespace EduNestIO.Tests;

/// <summary>
/// Academic Setup module tests over real HTTP + PostgreSQL. Skipped (no-op) when
/// EDUNESTIO_TEST_DB is not set.
/// </summary>
[Collection("integration")]
public sealed class AcademicTests
{
    private readonly IntegrationFixture _fx;
    public AcademicTests(IntegrationFixture fx) => _fx = fx;
    private static bool NoDb => !IntegrationFixture.DbAvailable;

    [Fact]
    public async Task Admin_can_create_and_list_class()
    {
        if (NoDb) return;
        var client = await _fx.LoginAsync("riverdale.admin");

        var unique = "IT-Class-" + Guid.NewGuid().ToString("N")[..6];
        var create = await client.PostAsJsonAsync("/api/academic/classes", new { Name = unique, Ordinal = 99 });
        Assert.Equal(HttpStatusCode.Created, create.StatusCode);

        var list = await client.GetAsync("/api/academic/classes");
        Assert.Equal(HttpStatusCode.OK, list.StatusCode);
        var body = JObject.Parse(await list.Content.ReadAsStringAsync());
        var items = (JArray)body["data"]!["items"]!;
        Assert.Contains(items, i => i["name"]!.ToString() == unique);
    }

    [Fact]
    public async Task Teacher_cannot_manage_academic_setup_403()
    {
        if (NoDb) return;
        var client = await _fx.LoginAsync("riverdale.teacher"); // academic.view only
        var resp = await client.PostAsJsonAsync("/api/academic/classes", new { Name = "No", Ordinal = 1 });
        Assert.Equal(HttpStatusCode.Forbidden, resp.StatusCode);
    }

    [Fact]
    public async Task Class_list_is_tenant_scoped()
    {
        if (NoDb) return;

        var unique = "RVD-Only-" + Guid.NewGuid().ToString("N")[..6];
        var riverdale = await _fx.LoginAsync("riverdale.admin");
        await riverdale.PostAsJsonAsync("/api/academic/classes", new { Name = unique, Ordinal = 50 });

        // Hillside (tenant 2) must not see Riverdale's class.
        var hillside = await _fx.LoginAsync("hillside.admin");
        var body = JObject.Parse(await (await hillside.GetAsync("/api/academic/classes")).Content.ReadAsStringAsync());
        var items = (JArray)body["data"]!["items"]!;
        Assert.DoesNotContain(items, i => i["name"]!.ToString() == unique);
    }

    [Fact]
    public async Task Subject_requires_name_and_code()
    {
        if (NoDb) return;
        var client = await _fx.LoginAsync("riverdale.admin");
        var resp = await client.PostAsJsonAsync("/api/academic/subjects", new { Name = "", Code = "" });
        Assert.Equal(HttpStatusCode.BadRequest, resp.StatusCode);
    }
}
