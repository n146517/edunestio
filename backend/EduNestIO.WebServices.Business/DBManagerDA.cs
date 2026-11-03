using EduNestIO.Common.Data;
using EduNestIO.Common.Logging;
using EduNestIO.WebServices.DataAccess;

namespace EduNestIO.WebServices.Business;

/// <summary>
/// Factory that hands out DA (data-access) objects by type and releases them when
/// done. Mirrors the reference project's DBManagerDA: BL classes call
/// GetDBObject(DAType.X) and ReleaseDBObject(da) in a finally block. Each call
/// constructs a DA bound to the default connection string; Npgsql pools the
/// underlying connections.
/// </summary>
public static class DBManagerDA
{
    public enum DAType
    {
        None = 0,
        Common = 1,
        Auth = 2,
        Student = 3,
        User = 4,
        Academic = 5,
        Admission = 6,
        Attendance = 7,
        Fee = 8,
        Exam = 9,
        Leave = 10,
        Settings = 11,
        Timetable = 12,
        Assignment = 13
    }

    public static DBBase? GetDBObject(DAType type, string connectionName = "")
    {
        DBBase? db = type switch
        {
            DAType.Common     => new CommonDA(connectionName),
            DAType.Auth       => new AuthDA(connectionName),
            DAType.Student    => new StudentDA(connectionName),
            DAType.User       => new UserDA(connectionName),
            DAType.Academic   => new AcademicDA(connectionName),
            DAType.Admission  => new AdmissionDA(connectionName),
            DAType.Attendance => new AttendanceDA(connectionName),
            DAType.Fee        => new FeeDA(connectionName),
            DAType.Exam       => new ExamDA(connectionName),
            DAType.Leave      => new LeaveDA(connectionName),
            DAType.Settings   => new SettingsDA(connectionName),
            DAType.Timetable  => new TimetableDA(connectionName),
            DAType.Assignment => new AssignmentDA(connectionName),
            _ => null
        };
        return db;
    }

    /// <summary>Releases the DA's connection back to the pool. Safe on null.</summary>
    public static void ReleaseDBObject(DBBase? db)
    {
        try
        {
            db?.DbMaster?.Disconnect();
        }
        catch (Exception ex)
        {
            LogWriter.WriteLog(new LogDTO
            {
                FunctionName = nameof(ReleaseDBObject),
                ClassName = nameof(DBManagerDA),
                LogStringLevel = LoggingLevel.Exceptional,
                ExceptionString = ex.Message,
                StackTrace = ex.StackTrace
            });
        }
    }
}
