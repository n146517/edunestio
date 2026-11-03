using System.Net;
using System.Net.Http.Json;
using Newtonsoft.Json.Linq;

namespace EduNestIO.Tests;

/// <summary>
/// Tests for the student enrollment-history / academic-progression feature
/// (Option A): promote keeps the student Active in the new class and records the
/// old class as Promoted; graduate/withdraw are terminal. Real HTTP + real
/// PostgreSQL; no-op when EDUNESTIO_TEST_DB is unset.
/// </summary>
[Collection("integration")]
public sealed class EnrollmentTests
{
    private readonly IntegrationFixture _fx;
    public EnrollmentTests(IntegrationFixture fx) => _fx = fx;
    private static bool NoDb => !IntegrationFixture.DbAvailable;

    private const long Grade1 = 1;
    private const long Grade2 = 2;

    private static async Task<long> CreateInGrade1Async(HttpClient client, string last)
    {
        var resp = await client.PostAsJsonAsync("/api/students",
            new { FirstName = "Enr", LastName = last, ClassId = Grade1 });
        resp.EnsureSuccessStatusCode();
        return (long)JObject.Parse(await resp.Content.ReadAsStringAsync())["data"]!["student_id"]!;
    }

    private static async Task<JArray> EnrollmentsAsync(HttpClient client, long id)
    {
        var resp = await client.GetAsync($"/api/students/{id}/enrollments");
        var body = JObject.Parse(await resp.Content.ReadAsStringAsync());
        return (JArray)body["data"]!["items"]!;
    }

    [Fact]
    public async Task New_student_gets_an_active_enrollment_automatically()
    {
        if (NoDb) return;
        var admin = await _fx.LoginAsync("riverdale.admin");
        var id = await CreateInGrade1Async(admin, "AutoEnroll");

        var items = await EnrollmentsAsync(admin, id);
        Assert.Single(items);
        Assert.Equal("Active", items[0]!["status"]!.ToString());
        Assert.Equal(Grade1, (long)items[0]!["class_id"]!);
    }

    [Fact]
    public async Task Promote_closes_old_enrollment_and_opens_new_active_student_stays_active()
    {
        if (NoDb) return;
        var admin = await _fx.LoginAsync("riverdale.admin");
        var id = await CreateInGrade1Async(admin, "Promote");

        var promote = await admin.PostAsJsonAsync("/api/students/promote",
            new { StudentIds = new[] { id }, ToClassId = Grade2, Note = "Passed" });
        Assert.Equal(HttpStatusCode.OK, promote.StatusCode);
        Assert.Equal(1, (int)JObject.Parse(await promote.Content.ReadAsStringAsync())["data"]!["promoted"]!);

        // History: Grade 2 Active (current) + Grade 1 Promoted.
        var items = await EnrollmentsAsync(admin, id);
        Assert.Equal(2, items.Count);
        var active = items.First(i => i["status"]!.ToString() == "Active");
        var promoted = items.First(i => i["status"]!.ToString() == "Promoted");
        Assert.Equal(Grade2, (long)active["class_id"]!);
        Assert.Equal(Grade1, (long)promoted["class_id"]!);

        // The student record itself stays Active, now in Grade 2.
        var student = JObject.Parse(await (await admin.GetAsync($"/api/students/{id}")).Content.ReadAsStringAsync())["data"]!;
        Assert.Equal("Active", student["status"]!.ToString());
        Assert.Equal(Grade2, (long)student["class_id"]!);
    }

    [Fact]
    public async Task Graduate_sets_student_graduated()
    {
        if (NoDb) return;
        var admin = await _fx.LoginAsync("riverdale.admin");
        var id = await CreateInGrade1Async(admin, "Graduate");

        var grad = await admin.PostAsJsonAsync("/api/students/graduate",
            new { StudentIds = new[] { id }, Note = "Completed" });
        Assert.Equal(HttpStatusCode.OK, grad.StatusCode);

        var student = JObject.Parse(await (await admin.GetAsync($"/api/students/{id}")).Content.ReadAsStringAsync())["data"]!;
        Assert.Equal("Graduated", student["status"]!.ToString());
        var items = await EnrollmentsAsync(admin, id);
        Assert.Contains(items, i => i["status"]!.ToString() == "Graduated");
    }

    [Fact]
    public async Task Withdraw_sets_student_withdrawn()
    {
        if (NoDb) return;
        var admin = await _fx.LoginAsync("riverdale.admin");
        var id = await CreateInGrade1Async(admin, "Withdraw");

        var wd = await admin.PostAsJsonAsync("/api/students/withdraw",
            new { StudentIds = new[] { id }, Reason = "Moved city" });
        Assert.Equal(HttpStatusCode.OK, wd.StatusCode);

        var student = JObject.Parse(await (await admin.GetAsync($"/api/students/{id}")).Content.ReadAsStringAsync())["data"]!;
        Assert.Equal("Withdrawn", student["status"]!.ToString());
    }

    [Fact]
    public async Task Inactive_student_is_not_promoted()
    {
        if (NoDb) return;
        var admin = await _fx.LoginAsync("riverdale.admin");
        var id = await CreateInGrade1Async(admin, "InactivePromote");

        // Deactivate -> Inactive.
        await admin.PostAsJsonAsync($"/api/students/{id}/status", new { Status = "Inactive", Reason = "test" });

        // Attempt to promote -> 0 promoted, student untouched.
        var promote = await admin.PostAsJsonAsync("/api/students/promote",
            new { StudentIds = new[] { id }, ToClassId = Grade2 });
        Assert.Equal(HttpStatusCode.OK, promote.StatusCode);
        Assert.Equal(0, (int)JObject.Parse(await promote.Content.ReadAsStringAsync())["data"]!["promoted"]!);

        var student = JObject.Parse(await (await admin.GetAsync($"/api/students/{id}")).Content.ReadAsStringAsync())["data"]!;
        Assert.Equal("Inactive", student["status"]!.ToString());
        Assert.Equal(Grade1, (long)student["class_id"]!);
    }

    [Fact]
    public async Task Bulk_promote_moves_multiple_students()
    {
        if (NoDb) return;
        var admin = await _fx.LoginAsync("riverdale.admin");
        var a = await CreateInGrade1Async(admin, "Bulk1");
        var b = await CreateInGrade1Async(admin, "Bulk2");

        var promote = await admin.PostAsJsonAsync("/api/students/promote",
            new { StudentIds = new[] { a, b }, ToClassId = Grade2 });
        Assert.Equal(HttpStatusCode.OK, promote.StatusCode);
        Assert.Equal(2, (int)JObject.Parse(await promote.Content.ReadAsStringAsync())["data"]!["promoted"]!);
    }

    [Fact]
    public async Task Teacher_cannot_promote_403()
    {
        if (NoDb) return;
        var admin = await _fx.LoginAsync("riverdale.admin");
        var id = await CreateInGrade1Async(admin, "TeacherGuard");

        var teacher = await _fx.LoginAsync("riverdale.teacher"); // no student.promote
        var resp = await teacher.PostAsJsonAsync("/api/students/promote",
            new { StudentIds = new[] { id }, ToClassId = Grade2 });
        Assert.Equal(HttpStatusCode.Forbidden, resp.StatusCode);
    }

    [Fact]
    public async Task Cross_tenant_promote_affects_nothing()
    {
        if (NoDb) return;
        var admin = await _fx.LoginAsync("riverdale.admin");
        var id = await CreateInGrade1Async(admin, "XTenant");

        // Hillside (tenant 2) attempts to promote using a tenant-1 class id. The
        // target-class validation runs against the caller's tenant, so Grade 2 (which
        // belongs to tenant 1) is rejected as an invalid class -> 400. Either way,
        // no cross-tenant write happens.
        var hillside = await _fx.LoginAsync("hillside.admin");
        var resp = await hillside.PostAsJsonAsync("/api/students/promote",
            new { StudentIds = new[] { id }, ToClassId = Grade2 });
        Assert.Equal(HttpStatusCode.BadRequest, resp.StatusCode);

        // The tenant-1 student is untouched (still Active in Grade 1).
        var student = JObject.Parse(await (await admin.GetAsync($"/api/students/{id}")).Content.ReadAsStringAsync())["data"]!;
        Assert.Equal(Grade1, (long)student["class_id"]!);
        Assert.Equal("Active", student["status"]!.ToString());
    }
}
