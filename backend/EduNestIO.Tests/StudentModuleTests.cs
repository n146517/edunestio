using System.Net;
using System.Net.Http.Json;
using Newtonsoft.Json.Linq;

namespace EduNestIO.Tests;

/// <summary>
/// Tests for the enhanced Students module: summary counts, filters, create with the
/// new fields, edit preserving the admission number, section/roll validation,
/// status changes + reactivation, and permission/tenant enforcement. Real HTTP +
/// real PostgreSQL; no-op when EDUNESTIO_TEST_DB is unset.
/// </summary>
[Collection("integration")]
public sealed class StudentModuleTests
{
    private readonly IntegrationFixture _fx;
    public StudentModuleTests(IntegrationFixture fx) => _fx = fx;
    private static bool NoDb => !IntegrationFixture.DbAvailable;

    private const long ClassId = 1; // Riverdale Grade 1

    private static string Rnd() => Guid.NewGuid().ToString("N")[..8];

    private static async Task<(long id, string adm)> CreateAsync(HttpClient client, object body)
    {
        var resp = await client.PostAsJsonAsync("/api/students", body);
        Assert.Equal(HttpStatusCode.Created, resp.StatusCode);
        var j = JObject.Parse(await resp.Content.ReadAsStringAsync());
        return ((long)j["data"]!["student_id"]!, j["data"]!["admission_number"]!.ToString());
    }

    [Fact]
    public async Task Summary_returns_status_counts()
    {
        if (NoDb) return;
        var admin = await _fx.LoginAsync("riverdale.admin");
        var resp = await admin.GetAsync("/api/students/summary");
        Assert.Equal(HttpStatusCode.OK, resp.StatusCode);
        var data = JObject.Parse(await resp.Content.ReadAsStringAsync())["data"]!;
        // Shape check — all count keys present and numeric.
        Assert.True((int)data["total"]! >= 0);
        Assert.NotNull(data["active"]);
        Assert.NotNull(data["inactive"]);
        Assert.NotNull(data["graduated"]);
        Assert.NotNull(data["withdrawn"]);
    }

    [Fact]
    public async Task Create_with_new_fields_persists_and_is_readable()
    {
        if (NoDb) return;
        var admin = await _fx.LoginAsync("riverdale.admin");
        var roll = "R-" + Rnd();
        var (id, adm) = await CreateAsync(admin, new
        {
            FirstName = "Guarded",
            LastName = "Child",
            ClassId,
            RollNumber = roll,
            GuardianName = "Parent X",
            GuardianRelation = "Father",
            GuardianPhone = "9990001234",
            BloodGroup = "O+",
            Nationality = "Indian",
            AdmissionDate = "2026-04-01"
        });
        Assert.False(string.IsNullOrWhiteSpace(adm));

        var get = JObject.Parse(await (await admin.GetAsync($"/api/students/{id}")).Content.ReadAsStringAsync());
        var d = get["data"]!;
        Assert.Equal(roll, d["roll_number"]!.ToString());
        Assert.Equal("Parent X", d["guardian_name"]!.ToString());
        Assert.Equal("O+", d["blood_group"]!.ToString());
    }

    [Fact]
    public async Task Edit_preserves_admission_number_and_student_id()
    {
        if (NoDb) return;
        var admin = await _fx.LoginAsync("riverdale.admin");
        var (id, admBefore) = await CreateAsync(admin, new { FirstName = "Stable", LastName = "Number", ClassId });

        var upd = await admin.PutAsJsonAsync($"/api/students/{id}",
            new { FirstName = "StableEdited", LastName = "Number", ClassId });
        Assert.Equal(HttpStatusCode.OK, upd.StatusCode);

        var get = JObject.Parse(await (await admin.GetAsync($"/api/students/{id}")).Content.ReadAsStringAsync());
        var d = get["data"]!;
        Assert.Equal(id, (long)d["student_id"]!);           // id stable
        Assert.Equal(admBefore, d["admission_number"]!.ToString()); // admission number unchanged
        Assert.Equal("StableEdited", d["first_name"]!.ToString());
    }

    [Fact]
    public async Task Invalid_section_for_class_is_rejected_400()
    {
        if (NoDb) return;
        var admin = await _fx.LoginAsync("riverdale.admin");
        var resp = await admin.PostAsJsonAsync("/api/students",
            new { FirstName = "Bad", LastName = "Section", ClassId, SectionId = 999999 });
        Assert.Equal(HttpStatusCode.BadRequest, resp.StatusCode);
    }

    [Fact]
    public async Task Duplicate_roll_in_same_class_is_conflict_409()
    {
        if (NoDb) return;
        var admin = await _fx.LoginAsync("riverdale.admin");
        var roll = "DUP-" + Rnd();
        await CreateAsync(admin, new { FirstName = "First", LastName = "Roll", ClassId, RollNumber = roll });

        var resp = await admin.PostAsJsonAsync("/api/students",
            new { FirstName = "Second", LastName = "Roll", ClassId, RollNumber = roll });
        Assert.Equal(HttpStatusCode.Conflict, resp.StatusCode);
    }

    [Fact]
    public async Task Status_change_to_graduated_then_reactivate()
    {
        if (NoDb) return;
        var admin = await _fx.LoginAsync("riverdale.admin");
        var (id, _) = await CreateAsync(admin, new { FirstName = "Grad", LastName = "Flow", ClassId });

        var grad = await admin.PostAsJsonAsync($"/api/students/{id}/status",
            new { Status = "Graduated", Reason = "Completed" });
        Assert.Equal(HttpStatusCode.OK, grad.StatusCode);

        var afterGrad = JObject.Parse(await (await admin.GetAsync($"/api/students/{id}")).Content.ReadAsStringAsync());
        Assert.Equal("Graduated", afterGrad["data"]!["status"]!.ToString());

        var react = await admin.PostAsJsonAsync($"/api/students/{id}/status",
            new { Status = "Active", Reason = "Reactivated" });
        Assert.Equal(HttpStatusCode.OK, react.StatusCode);

        var afterReact = JObject.Parse(await (await admin.GetAsync($"/api/students/{id}")).Content.ReadAsStringAsync());
        Assert.Equal("Active", afterReact["data"]!["status"]!.ToString());
    }

    [Fact]
    public async Task Invalid_status_value_is_rejected_400()
    {
        if (NoDb) return;
        var admin = await _fx.LoginAsync("riverdale.admin");
        var (id, _) = await CreateAsync(admin, new { FirstName = "Bad", LastName = "Status", ClassId });
        var resp = await admin.PostAsJsonAsync($"/api/students/{id}/status", new { Status = "Expelled" });
        Assert.Equal(HttpStatusCode.BadRequest, resp.StatusCode);
    }

    [Fact]
    public async Task Teacher_cannot_change_status_403()
    {
        if (NoDb) return;
        var admin = await _fx.LoginAsync("riverdale.admin");
        var (id, _) = await CreateAsync(admin, new { FirstName = "Perm", LastName = "Check", ClassId });

        var teacher = await _fx.LoginAsync("riverdale.teacher"); // view only, no student.status
        var resp = await teacher.PostAsJsonAsync($"/api/students/{id}/status", new { Status = "Inactive" });
        Assert.Equal(HttpStatusCode.Forbidden, resp.StatusCode);
    }

    [Fact]
    public async Task Cross_tenant_status_change_is_404()
    {
        if (NoDb) return;
        var admin = await _fx.LoginAsync("riverdale.admin");
        var (id, _) = await CreateAsync(admin, new { FirstName = "XT", LastName = "Status", ClassId });

        var hillside = await _fx.LoginAsync("hillside.admin"); // tenant 2
        var resp = await hillside.PostAsJsonAsync($"/api/students/{id}/status", new { Status = "Inactive" });
        Assert.Equal(HttpStatusCode.NotFound, resp.StatusCode);
    }

    [Fact]
    public async Task Status_filter_returns_only_matching_students()
    {
        if (NoDb) return;
        var admin = await _fx.LoginAsync("riverdale.admin");
        var (id, _) = await CreateAsync(admin, new { FirstName = "Filter", LastName = "Case", ClassId });
        await admin.PostAsJsonAsync($"/api/students/{id}/status", new { Status = "Withdrawn", Reason = "left" });

        var resp = await admin.GetAsync("/api/students?status=Withdrawn&pageSize=100");
        var items = (JArray)JObject.Parse(await resp.Content.ReadAsStringAsync())["data"]!["items"]!;
        Assert.All(items, i => Assert.Equal("Withdrawn", i["status"]!.ToString()));
        Assert.Contains(items, i => (long)i["student_id"]! == id);
    }
}
