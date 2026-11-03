using EduNestIO.Common.DTOs;
using EduNestIO.WebServices.DataAccess;
using Newtonsoft.Json.Linq;
using static EduNestIO.WebServices.Business.DBManagerDA;

namespace EduNestIO.WebServices.Business;

/// <summary>Business logic for the Fees & Finance module.</summary>
public class FeeBL
{
    private static FeeDA Da() => (FeeDA)GetDBObject(DAType.Fee)!;

    private static JObject WithActor(object vo, long actorUserId)
    {
        var o = JObject.FromObject(vo);
        o["ActorUserId"] = actorUserId;
        return o;
    }

    public DbResult FeeHeadSave(int t, FeeHeadVO vo) { FeeDA? d = null; try { d = Da(); return d.FeeHeadSave(t, vo); } finally { ReleaseDBObject(d); } }
    public DbResult FeeHeadList(int t) { FeeDA? d = null; try { d = Da(); return d.FeeHeadList(t); } finally { ReleaseDBObject(d); } }

    public DbResult FeeStructureSave(int t, FeeStructureVO vo) { FeeDA? d = null; try { d = Da(); return d.FeeStructureSave(t, vo); } finally { ReleaseDBObject(d); } }
    public DbResult FeeStructureList(int t) { FeeDA? d = null; try { d = Da(); return d.FeeStructureList(t); } finally { ReleaseDBObject(d); } }

    public DbResult FeeAssign(int t, long actor, FeeAssignVO vo) { FeeDA? d = null; try { d = Da(); return d.FeeAssign(t, WithActor(vo, actor)); } finally { ReleaseDBObject(d); } }
    public DbResult Ledger(int t, long studentId) { FeeDA? d = null; try { d = Da(); return d.Ledger(t, studentId); } finally { ReleaseDBObject(d); } }

    public DbResult PaymentRecord(int t, long actor, PaymentVO vo) { FeeDA? d = null; try { d = Da(); return d.PaymentRecord(t, WithActor(vo, actor)); } finally { ReleaseDBObject(d); } }
    public DbResult PaymentReverse(int t, long actor, PaymentReverseVO vo) { FeeDA? d = null; try { d = Da(); return d.PaymentReverse(t, WithActor(vo, actor)); } finally { ReleaseDBObject(d); } }

    public DbResult Defaulters(int t, long? classId) { FeeDA? d = null; try { d = Da(); return d.Defaulters(t, classId); } finally { ReleaseDBObject(d); } }
    public DbResult Collection(int t, string? from, string? to) { FeeDA? d = null; try { d = Da(); return d.Collection(t, from, to); } finally { ReleaseDBObject(d); } }
}
