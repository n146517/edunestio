using EduNestIO.Common.Data;
using EduNestIO.Common.DTOs;

namespace EduNestIO.WebServices.DataAccess;

/// <summary>Data access for the Fees & Finance module.</summary>
public class FeeDA : DBBase
{
    public FeeDA(string connectionString = "") : base(connectionString) { }

    public DbResult FeeHeadSave(int t, object p) => DAHelper.ExecuteTenantJson(DbMaster, "finance.fn_fee_head_save", t, p);
    public DbResult FeeHeadList(int t) => DAHelper.ExecuteTenantJson(DbMaster, "finance.fn_fee_head_list", t, new { });

    public DbResult FeeStructureSave(int t, object p) => DAHelper.ExecuteTenantJson(DbMaster, "finance.fn_fee_structure_save", t, p);
    public DbResult FeeStructureList(int t) => DAHelper.ExecuteTenantJson(DbMaster, "finance.fn_fee_structure_list", t, new { });

    public DbResult FeeAssign(int t, object p) => DAHelper.ExecuteTenantJson(DbMaster, "finance.fn_fee_assign", t, p);
    public DbResult Ledger(int t, long studentId) => DAHelper.ExecuteTenantJson(DbMaster, "finance.fn_fee_ledger", t, new { student_id = studentId });

    public DbResult PaymentRecord(int t, object p) => DAHelper.ExecuteTenantJson(DbMaster, "finance.fn_payment_record", t, p);
    public DbResult PaymentReverse(int t, object p) => DAHelper.ExecuteTenantJson(DbMaster, "finance.fn_payment_reverse", t, p);

    public DbResult Defaulters(int t, long? classId) => DAHelper.ExecuteTenantJson(DbMaster, "finance.fn_fee_defaulters", t, new { class_id = classId });
    public DbResult Collection(int t, string? from, string? to) => DAHelper.ExecuteTenantJson(DbMaster, "finance.fn_fee_collection", t, new { from, to });
}
