using EduNestIO.Common.DTOs;
using EduNestIO.Common.Security;
using EduNestIO.WebServices.Business;
using EduNestIO.WebServices.RestAPI.Filters;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace EduNestIO.WebServices.RestAPI.Controllers;

/// <summary>
/// Fees and Finance: fee heads, structures, per-student demands, receipts (race-safe
/// numbering), ledgers, defaulters and collection reports. Money is handled as
/// decimal/NUMERIC end to end. Tenant-scoped; student/head ids re-validated in SQL.
/// </summary>
[ApiController]
[Route("api/fees")]
[Authorize]
[ServiceExceptionFilter]
public sealed class FeeController : BaseApiController
{
    private readonly FeeBL _bl = new();

    // Fee heads
    [HttpGet("heads")]
    [RequirePermission(Permissions.FeeView)]
    public ActionResult Heads() => Map(_bl.FeeHeadList(CurrentUser.TenantId));

    [HttpPost("heads")]
    [RequirePermission(Permissions.FeeManage)]
    public ActionResult SaveHead([FromBody] FeeHeadVO vo) => Map(_bl.FeeHeadSave(CurrentUser.TenantId, vo), vo.FeeHeadId is null);

    // Fee structures
    [HttpGet("structures")]
    [RequirePermission(Permissions.FeeView)]
    public ActionResult Structures() => Map(_bl.FeeStructureList(CurrentUser.TenantId));

    [HttpPost("structures")]
    [RequirePermission(Permissions.FeeManage)]
    public ActionResult SaveStructure([FromBody] FeeStructureVO vo) => Map(_bl.FeeStructureSave(CurrentUser.TenantId, vo), vo.FeeStructureId is null);

    // Assign a demand to a student
    [HttpPost("assign")]
    [RequirePermission(Permissions.FeeManage)]
    public ActionResult Assign([FromBody] FeeAssignVO vo) => Map(_bl.FeeAssign(CurrentUser.TenantId, CurrentUser.UserId, vo), created: true);

    // Student fee ledger (balances)
    [HttpGet("ledger/{studentId:long}")]
    [RequirePermission(Permissions.FeeView)]
    public ActionResult Ledger(long studentId) => Map(_bl.Ledger(CurrentUser.TenantId, studentId));

    // Record a payment (receipt)
    [HttpPost("payments")]
    [RequirePermission(Permissions.FeeCollect)]
    public ActionResult Pay([FromBody] PaymentVO vo) => Map(_bl.PaymentRecord(CurrentUser.TenantId, CurrentUser.UserId, vo), created: true);

    // Reverse a payment
    [HttpPost("payments/reverse")]
    [RequirePermission(Permissions.FeeReverse)]
    public ActionResult Reverse([FromBody] PaymentReverseVO vo) => Map(_bl.PaymentReverse(CurrentUser.TenantId, CurrentUser.UserId, vo));

    // Reports
    [HttpGet("defaulters")]
    [RequirePermission(Permissions.FeeView)]
    public ActionResult Defaulters([FromQuery] long? classId) => Map(_bl.Defaulters(CurrentUser.TenantId, classId));

    [HttpGet("collection")]
    [RequirePermission(Permissions.FeeView)]
    public ActionResult Collection([FromQuery] string? from, [FromQuery] string? to) => Map(_bl.Collection(CurrentUser.TenantId, from, to));
}
