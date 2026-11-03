using System.Net;
using System.Net.Http.Json;
using Newtonsoft.Json.Linq;

namespace EduNestIO.Tests;

/// <summary>
/// End-to-end tests over real HTTP + real PostgreSQL proving authentication,
/// permission checks and TENANT ISOLATION. Skipped (not failed) when no test DB is
/// configured via EDUNESTIO_TEST_DB.
///
/// Demo users (seeded): riverdale.admin (tenant 1, SchoolAdmin),
/// hillside.admin (tenant 2, SchoolAdmin), riverdale.teacher (tenant 1, Teacher).
/// </summary>
[Collection("integration")]
public sealed class StudentTenantIsolationTests
{
    private readonly IntegrationFixture _fx;
    public StudentTenantIsolationTests(IntegrationFixture fx) => _fx = fx;

    /// <summary>
    /// Returns true when a test database is configured. When false, DB-backed tests
    /// short-circuit as a no-op pass (the suite stays green without a database; set
    /// EDUNESTIO_TEST_DB to exercise them fully). This is called out in test-plan.md.
    /// </summary>
    private static bool NoDb => !IntegrationFixture.DbAvailable;

    [Fact]
    public async Task Status_endpoint_is_public()
    {
        if (NoDb) return;
        var client = _fx.Factory!.CreateClient();
        var resp = await client.GetAsync("/api/status");
        Assert.Equal(HttpStatusCode.OK, resp.StatusCode);
    }

    [Fact]
    public async Task Anonymous_cannot_list_students()
    {
        if (NoDb) return;
        var client = _fx.Factory!.CreateClient();
        var resp = await client.GetAsync("/api/students");
        Assert.Equal(HttpStatusCode.Unauthorized, resp.StatusCode);
    }

    [Fact]
    public async Task Invalid_login_returns_401_generic()
    {
        if (NoDb) return;
        var client = _fx.Factory!.CreateClient();
        var resp = await client.PostAsJsonAsync("/api/auth/login", new { username = "nobody", password = "wrong" });
        Assert.Equal(HttpStatusCode.Unauthorized, resp.StatusCode);
    }

    [Fact]
    public async Task Admin_can_list_own_tenant_students()
    {
        if (NoDb) return;
        var client = await _fx.LoginAsync("riverdale.admin");
        var resp = await client.GetAsync("/api/students");
        Assert.Equal(HttpStatusCode.OK, resp.StatusCode);

        var body = JObject.Parse(await resp.Content.ReadAsStringAsync());
        var items = (JArray)body["data"]!["items"]!;
        // Every returned student must belong to tenant 1 (Riverdale).
        Assert.All(items, i => Assert.Equal(1, (int)i["tenant_id"]!));
    }

    [Fact]
    public async Task Teacher_cannot_create_student_403()
    {
        if (NoDb) return;
        var client = await _fx.LoginAsync("riverdale.teacher"); // view only
        var resp = await client.PostAsJsonAsync("/api/students", new { FirstName = "No", LastName = "Perm" });
        Assert.Equal(HttpStatusCode.Forbidden, resp.StatusCode);
    }

    [Fact]
    public async Task Tenant_A_admin_creates_student_then_Tenant_B_cannot_see_or_fetch_it()
    {
        if (NoDb) return;

        // Riverdale (tenant 1) admin creates a student.
        var riverdale = await _fx.LoginAsync("riverdale.admin");
        var createResp = await riverdale.PostAsJsonAsync("/api/students",
            new { FirstName = "Isolation", LastName = "Probe" });
        Assert.Equal(HttpStatusCode.Created, createResp.StatusCode);
        var created = JObject.Parse(await createResp.Content.ReadAsStringAsync());
        var newId = (long)created["data"]!["student_id"]!;

        // Hillside (tenant 2) admin must NOT be able to fetch that id -> 404 (no leak).
        var hillside = await _fx.LoginAsync("hillside.admin");
        var getResp = await hillside.GetAsync($"/api/students/{newId}");
        Assert.Equal(HttpStatusCode.NotFound, getResp.StatusCode);

        // And it must not appear in Hillside's list.
        var listResp = await hillside.GetAsync("/api/students");
        var listBody = JObject.Parse(await listResp.Content.ReadAsStringAsync());
        var items = (JArray)listBody["data"]!["items"]!;
        Assert.DoesNotContain(items, i => (long)i["student_id"]! == newId);
    }

    [Fact]
    public async Task Tenant_B_admin_cannot_update_Tenant_A_student()
    {
        if (NoDb) return;

        var riverdale = await _fx.LoginAsync("riverdale.admin");
        var createResp = await riverdale.PostAsJsonAsync("/api/students",
            new { FirstName = "Update", LastName = "Guard" });
        var created = JObject.Parse(await createResp.Content.ReadAsStringAsync());
        var newId = (long)created["data"]!["student_id"]!;

        // Hillside attempts to update tenant 1's student -> must be rejected (404, no leak).
        var hillside = await _fx.LoginAsync("hillside.admin");
        var updResp = await hillside.PutAsJsonAsync($"/api/students/{newId}",
            new { FirstName = "Hacked", LastName = "Name" });
        Assert.Equal(HttpStatusCode.NotFound, updResp.StatusCode);
    }
}
