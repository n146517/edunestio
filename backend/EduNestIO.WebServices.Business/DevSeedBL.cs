using EduNestIO.Common.Logging;
using EduNestIO.Common.Security;
using EduNestIO.WebServices.DataAccess;
using static EduNestIO.WebServices.Business.DBManagerDA;

namespace EduNestIO.WebServices.Business;

/// <summary>
/// Development-only seeding of demo users with securely hashed passwords. Runs on
/// startup only when enabled (Development). Idempotent via core.fn_upsert_user.
/// The demo password is supplied via configuration/environment — never hard-coded.
/// </summary>
public class DevSeedBL
{
    public void SeedDemoUsers(string demoPassword)
    {
        if (string.IsNullOrWhiteSpace(demoPassword))
        {
            LogWriter.WriteLog(new LogDTO { FunctionName = nameof(SeedDemoUsers), ClassName = GetType().Name, Message = "No demo password; skipping user seed." });
            return;
        }

        UserDA? da = null;
        try
        {
            da = (UserDA)GetDBObject(DAType.User)!;

            // Platform super admin (tenant 0 -> NULL)
            SeedOne(da, 0, "superadmin", "superadmin@edunest.local", "Platform Super Admin", demoPassword,
                new[] { Roles.SaaSSuperAdmin });

            // Tenant 1 (Riverdale) admin + teacher
            SeedOne(da, 1, "riverdale.admin", "admin@riverdale.local", "Riverdale Admin", demoPassword,
                new[] { Roles.SchoolAdmin });
            SeedOne(da, 1, "riverdale.teacher", "teacher@riverdale.local", "Riverdale Teacher", demoPassword,
                new[] { Roles.Teacher });
            // Demo student self-service account (linked to a student row in migration 25).
            SeedOne(da, 1, "riverdale.student", "student@riverdale.local", "Pramod Pramod", demoPassword,
                new[] { Roles.Student });

            // Tenant 2 (Hillside) admin
            SeedOne(da, 2, "hillside.admin", "admin@hillside.local", "Hillside Admin", demoPassword,
                new[] { Roles.SchoolAdmin });

            LogWriter.WriteLog(new LogDTO { FunctionName = nameof(SeedDemoUsers), ClassName = GetType().Name, Message = "Demo users seeded." });
        }
        finally
        {
            ReleaseDBObject(da);
        }
    }

    private static void SeedOne(UserDA da, int tenantId, string username, string email, string fullName, string password, string[] roles)
    {
        var (hash, salt) = PasswordHasher.Hash(password);
        da.UpsertUser(tenantId, new
        {
            username,
            email,
            full_name = fullName,
            password_hash = hash,
            password_salt = salt,
            roles
        });
    }
}
