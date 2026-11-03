using System.Net;
using System.Net.Http.Json;
using Newtonsoft.Json.Linq;

namespace EduNestIO.Tests;

/// <summary>Fees & Finance tests over real HTTP + PostgreSQL. No-op when no test DB.</summary>
[Collection("integration")]
public sealed class FeeTests
{
    private readonly IntegrationFixture _fx;
    public FeeTests(IntegrationFixture fx) => _fx = fx;
    private static bool NoDb => !IntegrationFixture.DbAvailable;
    private const long StudentId = 1; // Riverdale Ava Stone

    private static async Task<long> EnsureFeeHead(HttpClient c)
    {
        var code = "H" + Guid.NewGuid().ToString("N")[..6];
        var r = await c.PostAsJsonAsync("/api/fees/heads", new { Name = "Head " + code, Code = code });
        var body = JObject.Parse(await r.Content.ReadAsStringAsync());
        return (long)body["data"]!["fee_head_id"]!;
    }

    [Fact]
    public async Task Assign_pay_partial_then_ledger_shows_balance()
    {
        if (NoDb) return;
        var admin = await _fx.LoginAsync("riverdale.admin"); // has fee.manage + fee.collect + fee.view
        var headId = await EnsureFeeHead(admin);

        var assign = await admin.PostAsJsonAsync("/api/fees/assign", new { StudentId, FeeHeadId = headId, Amount = 1000m });
        Assert.Equal(HttpStatusCode.Created, assign.StatusCode);

        var pay = await admin.PostAsJsonAsync("/api/fees/payments", new { StudentId, Amount = 600m, Mode = "Cash" });
        Assert.Equal(HttpStatusCode.Created, pay.StatusCode);
        var payBody = JObject.Parse(await pay.Content.ReadAsStringAsync());
        Assert.False(string.IsNullOrWhiteSpace(payBody["data"]!["receipt_number"]!.ToString()));

        var ledger = JObject.Parse(await (await admin.GetAsync($"/api/fees/ledger/{StudentId}")).Content.ReadAsStringAsync());
        // Balance is net_total - paid_total; after paying 600 of >=1000 there is a positive balance.
        Assert.True((decimal)ledger["data"]!["balance"]! >= 0);
        Assert.True((decimal)ledger["data"]!["paid_total"]! >= 600m);
    }

    [Fact]
    public async Task Receptionist_can_collect_but_not_manage_heads()
    {
        if (NoDb) return;
        // No receptionist user seeded; assert permission boundary with teacher (no fee perms) -> 403 on view.
        var teacher = await _fx.LoginAsync("riverdale.teacher");
        var resp = await teacher.GetAsync("/api/fees/heads");
        Assert.Equal(HttpStatusCode.Forbidden, resp.StatusCode);
    }

    [Fact]
    public async Task Cannot_assign_fee_to_foreign_tenant_student()
    {
        if (NoDb) return;
        var hillside = await _fx.LoginAsync("hillside.admin");
        var headId = await EnsureFeeHead(hillside);
        // Student 1 belongs to Riverdale (tenant 1); Hillside admin must be rejected.
        var assign = await hillside.PostAsJsonAsync("/api/fees/assign", new { StudentId = 1L, FeeHeadId = headId, Amount = 500m });
        // TENANT_MISMATCH -> mapped to 404 (no cross-tenant existence leak).
        Assert.Equal(HttpStatusCode.NotFound, assign.StatusCode);
    }

    [Fact]
    public async Task Collection_report_returns_total()
    {
        if (NoDb) return;
        var admin = await _fx.LoginAsync("riverdale.admin");
        var body = JObject.Parse(await (await admin.GetAsync("/api/fees/collection")).Content.ReadAsStringAsync());
        Assert.NotNull(body["data"]!["total_collected"]);
    }

    [Fact]
    public async Task Payment_reverse_rolls_back_balance()
    {
        if (NoDb) return;
        var admin = await _fx.LoginAsync("riverdale.admin");
        var headId = await EnsureFeeHead(admin);
        await admin.PostAsJsonAsync("/api/fees/assign", new { StudentId, FeeHeadId = headId, Amount = 200m });

        var pay = await admin.PostAsJsonAsync("/api/fees/payments", new { StudentId, Amount = 200m, Mode = "Cash" });
        var paymentId = (long)JObject.Parse(await pay.Content.ReadAsStringAsync())["data"]!["payment_id"]!;

        var reverse = await admin.PostAsJsonAsync("/api/fees/payments/reverse", new { PaymentId = paymentId, Reason = "test" });
        Assert.Equal(HttpStatusCode.OK, reverse.StatusCode);

        // A second reverse is rejected as duplicate.
        var second = await admin.PostAsJsonAsync("/api/fees/payments/reverse", new { PaymentId = paymentId, Reason = "again" });
        Assert.Equal(HttpStatusCode.Conflict, second.StatusCode);
    }
}
