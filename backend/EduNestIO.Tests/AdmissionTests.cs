using System.Net;
using System.Net.Http.Json;
using Newtonsoft.Json.Linq;

namespace EduNestIO.Tests;

/// <summary>
/// Admissions & Enquiry CRM tests over real HTTP + PostgreSQL. No-op when no test DB.
/// </summary>
[Collection("integration")]
public sealed class AdmissionTests
{
    private readonly IntegrationFixture _fx;
    public AdmissionTests(IntegrationFixture fx) => _fx = fx;
    private static bool NoDb => !IntegrationFixture.DbAvailable;

    [Fact]
    public async Task Create_enquiry_generates_number()
    {
        if (NoDb) return;
        var client = await _fx.LoginAsync("riverdale.admin");
        var resp = await client.PostAsJsonAsync("/api/admissions/enquiries",
            new { ApplicantName = "Test Applicant", Source = "Website" });
        Assert.Equal(HttpStatusCode.Created, resp.StatusCode);
        var body = JObject.Parse(await resp.Content.ReadAsStringAsync());
        Assert.False(string.IsNullOrWhiteSpace(body["data"]!["enquiry_number"]!.ToString()));
    }

    [Fact]
    public async Task Convert_enquiry_creates_student_and_marks_admitted()
    {
        if (NoDb) return;
        var client = await _fx.LoginAsync("riverdale.admin");

        var create = await client.PostAsJsonAsync("/api/admissions/enquiries",
            new { ApplicantName = "Convert Me" });
        var created = JObject.Parse(await create.Content.ReadAsStringAsync());
        var enquiryId = (long)created["data"]!["enquiry_id"]!;

        var convert = await client.PostAsJsonAsync($"/api/admissions/enquiries/{enquiryId}/convert", new { });
        Assert.Equal(HttpStatusCode.Created, convert.StatusCode);
        var conv = JObject.Parse(await convert.Content.ReadAsStringAsync());
        var studentId = (long)conv["data"]!["student_id"]!;
        Assert.True(studentId > 0);

        // The new student is visible in the same tenant's student list.
        var students = JObject.Parse(await (await client.GetAsync("/api/students?pageSize=100")).Content.ReadAsStringAsync());
        var items = (JArray)students["data"]!["items"]!;
        Assert.Contains(items, i => (long)i["student_id"]! == studentId);
    }

    [Fact]
    public async Task Double_convert_is_rejected()
    {
        if (NoDb) return;
        var client = await _fx.LoginAsync("riverdale.admin");
        var create = await client.PostAsJsonAsync("/api/admissions/enquiries", new { ApplicantName = "Once Only" });
        var enquiryId = (long)JObject.Parse(await create.Content.ReadAsStringAsync())["data"]!["enquiry_id"]!;

        await client.PostAsJsonAsync($"/api/admissions/enquiries/{enquiryId}/convert", new { });
        var second = await client.PostAsJsonAsync($"/api/admissions/enquiries/{enquiryId}/convert", new { });
        Assert.Equal(HttpStatusCode.Conflict, second.StatusCode); // DUPLICATE -> 409
    }

    [Fact]
    public async Task Tenant_B_cannot_see_Tenant_A_enquiry()
    {
        if (NoDb) return;
        var unique = "Probe-" + Guid.NewGuid().ToString("N")[..6];
        var riverdale = await _fx.LoginAsync("riverdale.admin");
        await riverdale.PostAsJsonAsync("/api/admissions/enquiries", new { ApplicantName = unique });

        var hillside = await _fx.LoginAsync("hillside.admin");
        var body = JObject.Parse(await (await hillside.GetAsync("/api/admissions/enquiries?pageSize=100")).Content.ReadAsStringAsync());
        var items = (JArray)body["data"]!["items"]!;
        Assert.DoesNotContain(items, i => i["applicant_name"]!.ToString() == unique);
    }

    [Fact]
    public async Task Teacher_cannot_create_enquiry_403()
    {
        if (NoDb) return;
        var client = await _fx.LoginAsync("riverdale.teacher");
        var resp = await client.PostAsJsonAsync("/api/admissions/enquiries", new { ApplicantName = "No" });
        Assert.Equal(HttpStatusCode.Forbidden, resp.StatusCode);
    }
}
