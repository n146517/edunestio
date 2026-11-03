using System.Net;
using System.Net.Http.Json;
using Newtonsoft.Json.Linq;

namespace EduNestIO.Tests;

/// <summary>Exams and Report Cards tests over real HTTP + PostgreSQL. No-op when no test DB.</summary>
[Collection("integration")]
public sealed class ExamTests
{
    private readonly IntegrationFixture _fx;
    public ExamTests(IntegrationFixture fx) => _fx = fx;
    private static bool NoDb => !IntegrationFixture.DbAvailable;

    // Riverdale (tenant 1): class_id 1 = Grade 1; student 1 = Ava Stone.
    private const long ClassId = 1;
    private const long StudentId = 1;

    private static async Task<long> SubjectIdAsync(HttpClient client, string code)
    {
        // Academic subject list is exposed at /api/academic/subjects.
        var resp = await client.GetAsync("/api/academic/subjects");
        var body = JObject.Parse(await resp.Content.ReadAsStringAsync());
        var items = (JArray)body["data"]!["items"]!;
        return (long)items.First(i => i["code"]!.ToString() == code)["subject_id"]!;
    }

    [Fact]
    public async Task Admin_full_flow_exam_subject_marks_publish_report()
    {
        if (NoDb) return;
        var admin = await _fx.LoginAsync("riverdale.admin");

        // Create exam with a unique name.
        var examName = "IT " + Guid.NewGuid().ToString("N")[..8];
        var create = await admin.PostAsJsonAsync("/api/exams",
            new { Name = examName, ExamType = "Term Exam", ClassIds = new[] { ClassId }, StartDate = "2026-04-01" });
        Assert.Equal(HttpStatusCode.Created, create.StatusCode);
        var examId = (long)JObject.Parse(await create.Content.ReadAsStringAsync())["data"]!["exam_id"]!;

        // Attach Mathematics.
        var subjectId = await SubjectIdAsync(admin, "MATH");
        var addSub = await admin.PostAsJsonAsync("/api/exams/subjects",
            new { ExamId = examId, SubjectId = subjectId, MaxMarks = 100, PassMarks = 33 });
        Assert.Equal(HttpStatusCode.Created, addSub.StatusCode);
        var examSubjectId = (long)JObject.Parse(await addSub.Content.ReadAsStringAsync())["data"]!["exam_subject_id"]!;

        // Sheet shows the class roster.
        var sheet = JObject.Parse(await (await admin.GetAsync($"/api/exams/subjects/{examSubjectId}/sheet")).Content.ReadAsStringAsync());
        var roster = (JArray)sheet["data"]!["items"]!;
        Assert.Contains(roster, i => (long)i["student_id"]! == StudentId);

        // Save marks (77/100).
        var save = await admin.PostAsJsonAsync("/api/exams/marks", new
        {
            ExamSubjectId = examSubjectId,
            Entries = new[] { new { StudentId, Marks = 77m, IsAbsent = false } }
        });
        Assert.Equal(HttpStatusCode.OK, save.StatusCode);
        Assert.Equal(1, (int)JObject.Parse(await save.Content.ReadAsStringAsync())["data"]!["saved"]!);

        // Publish (force past the missing-marks guard — this test only marks one student).
        var pub = await admin.PostAsJsonAsync("/api/exams/publish", new { ExamId = examId, Publish = true, Force = true });
        Assert.Equal(HttpStatusCode.OK, pub.StatusCode);

        // Report card computes percentage/grade/result.
        var report = JObject.Parse(await (await admin.GetAsync($"/api/exams/{examId}/report-card/{StudentId}")).Content.ReadAsStringAsync());
        var data = report["data"]!;
        Assert.Equal(77m, (decimal)data["percentage"]!);
        Assert.Equal("B", data["grade"]!.ToString());
        Assert.Equal("Pass", data["result"]!.ToString());
        Assert.True((bool)data["is_published"]!);
    }

    [Fact]
    public async Task Marks_above_max_are_rejected_400()
    {
        if (NoDb) return;
        var admin = await _fx.LoginAsync("riverdale.admin");
        var examName = "MX " + Guid.NewGuid().ToString("N")[..8];
        var examId = (long)JObject.Parse(await (await admin.PostAsJsonAsync("/api/exams",
            new { Name = examName, ClassIds = new[] { ClassId } })).Content.ReadAsStringAsync())["data"]!["exam_id"]!;
        var subjectId = await SubjectIdAsync(admin, "ENG");
        var examSubjectId = (long)JObject.Parse(await (await admin.PostAsJsonAsync("/api/exams/subjects",
            new { ExamId = examId, SubjectId = subjectId, MaxMarks = 50, PassMarks = 20 })).Content.ReadAsStringAsync())["data"]!["exam_subject_id"]!;

        var save = await admin.PostAsJsonAsync("/api/exams/marks", new
        {
            ExamSubjectId = examSubjectId,
            Entries = new[] { new { StudentId, Marks = 80m, IsAbsent = false } } // > 50
        });
        Assert.Equal(HttpStatusCode.BadRequest, save.StatusCode);
    }

    [Fact]
    public async Task Teacher_cannot_create_exam_403()
    {
        if (NoDb) return;
        var teacher = await _fx.LoginAsync("riverdale.teacher"); // exam.view + exam.marks, NOT exam.manage
        var resp = await teacher.PostAsJsonAsync("/api/exams", new { Name = "Nope", ClassIds = new[] { ClassId } });
        Assert.Equal(HttpStatusCode.Forbidden, resp.StatusCode);
    }

    [Fact]
    public async Task Teacher_cannot_publish_403()
    {
        if (NoDb) return;
        var admin = await _fx.LoginAsync("riverdale.admin");
        var examId = (long)JObject.Parse(await (await admin.PostAsJsonAsync("/api/exams",
            new { Name = "PB " + Guid.NewGuid().ToString("N")[..8], ClassIds = new[] { ClassId } })).Content.ReadAsStringAsync())["data"]!["exam_id"]!;

        var teacher = await _fx.LoginAsync("riverdale.teacher");
        var resp = await teacher.PostAsJsonAsync("/api/exams/publish", new { ExamId = examId, Publish = true });
        Assert.Equal(HttpStatusCode.Forbidden, resp.StatusCode);
    }

    [Fact]
    public async Task Cross_tenant_report_card_is_404()
    {
        if (NoDb) return;
        var admin = await _fx.LoginAsync("riverdale.admin");
        var examId = (long)JObject.Parse(await (await admin.PostAsJsonAsync("/api/exams",
            new { Name = "XT " + Guid.NewGuid().ToString("N")[..8], ClassIds = new[] { ClassId } })).Content.ReadAsStringAsync())["data"]!["exam_id"]!;

        var hillside = await _fx.LoginAsync("hillside.admin"); // tenant 2
        var resp = await hillside.GetAsync($"/api/exams/{examId}/report-card/{StudentId}");
        Assert.Equal(HttpStatusCode.NotFound, resp.StatusCode);
    }

    [Fact]
    public async Task Report_card_includes_header_and_class_list_works()
    {
        if (NoDb) return;
        var admin = await _fx.LoginAsync("riverdale.admin");
        var name = "RC " + Guid.NewGuid().ToString("N")[..8];
        var examId = (long)JObject.Parse(await (await admin.PostAsJsonAsync("/api/exams",
            new { Name = name, ExamType = "Term Exam", ClassIds = new[] { ClassId } })).Content.ReadAsStringAsync())["data"]!["exam_id"]!;
        var math = await SubjectIdAsync(admin, "MATH");
        await admin.PostAsJsonAsync("/api/exams/class-subjects", new
        {
            ExamId = examId, ClassId = ClassId,
            Subjects = new[] { new { SubjectId = math, MaxMarks = 100, PassMarks = 33, SubjectType = "Theory" } }
        });
        var subs = JObject.Parse(await (await admin.GetAsync($"/api/exams/{examId}/classes/{ClassId}/subjects")).Content.ReadAsStringAsync());
        var examSubjectId = (long)((JArray)subs["data"]!["items"]!)[0]!["exam_subject_id"]!;
        await admin.PostAsJsonAsync("/api/exams/marks", new
        {
            ExamSubjectId = examSubjectId,
            Entries = new[] { new { StudentId, Marks = 88m, IsAbsent = false } }
        });

        // Individual report card: has school + student header, single subject, grade/result.
        var rc = JObject.Parse(await (await admin.GetAsync($"/api/exams/{examId}/report-card/{StudentId}")).Content.ReadAsStringAsync())["data"]!;
        Assert.False(string.IsNullOrWhiteSpace(rc["exam"]!["school_name"]!.ToString()));
        Assert.Equal(StudentId, (long)rc["student"]!["student_id"]!);
        Assert.Single((JArray)rc["subjects"]!);          // only the student's class subject (no double-count)
        Assert.Equal(88m, (decimal)rc["percentage"]!);

        // Class-wise report list includes the student.
        var list = JObject.Parse(await (await admin.GetAsync($"/api/exams/{examId}/classes/{ClassId}/report-cards")).Content.ReadAsStringAsync())["data"]!;
        var items = (JArray)list["items"]!;
        Assert.Contains(items, i => (long)i["student_id"]! == StudentId);
    }

    [Fact]
    public async Task Result_preview_shows_ready_and_publish_succeeds_when_complete()
    {
        if (NoDb) return;
        var admin = await _fx.LoginAsync("riverdale.admin");
        var name = "RP " + Guid.NewGuid().ToString("N")[..8];
        var examId = (long)JObject.Parse(await (await admin.PostAsJsonAsync("/api/exams",
            new { Name = name, ExamType = "Term Exam", ClassIds = new[] { ClassId } })).Content.ReadAsStringAsync())["data"]!["exam_id"]!;
        var math = await SubjectIdAsync(admin, "MATH");
        await admin.PostAsJsonAsync("/api/exams/class-subjects", new
        {
            ExamId = examId, ClassId = ClassId,
            Subjects = new[] { new { SubjectId = math, MaxMarks = 100, PassMarks = 33, SubjectType = "Theory" } }
        });

        // Enter marks for EVERY active student in class 1 so nothing is missing.
        var subs = JObject.Parse(await (await admin.GetAsync($"/api/exams/{examId}/classes/{ClassId}/subjects")).Content.ReadAsStringAsync());
        var examSubjectId = (long)((JArray)subs["data"]!["items"]!)[0]!["exam_subject_id"]!;
        var sheet = JObject.Parse(await (await admin.GetAsync($"/api/exams/subjects/{examSubjectId}/sheet")).Content.ReadAsStringAsync());
        var roster = (JArray)sheet["data"]!["items"]!;
        var entries = roster.Select(r => new { StudentId = (long)r["student_id"]!, Marks = 70m, IsAbsent = false }).ToArray();
        await admin.PostAsJsonAsync("/api/exams/marks", new { ExamSubjectId = examSubjectId, Entries = entries });

        // Preview: everyone Ready, ready_to_publish true.
        var prev = JObject.Parse(await (await admin.GetAsync($"/api/exams/{examId}/classes/{ClassId}/results")).Content.ReadAsStringAsync());
        Assert.Equal(0, (int)prev["data"]!["missing"]!);
        Assert.True((bool)prev["data"]!["ready_to_publish"]!);

        // Publish succeeds without force.
        var pub = await admin.PostAsJsonAsync("/api/exams/publish", new { ExamId = examId, Publish = true });
        Assert.Equal(HttpStatusCode.OK, pub.StatusCode);
    }

    [Fact]
    public async Task Publish_blocked_on_missing_marks_until_forced()
    {
        if (NoDb) return;
        var admin = await _fx.LoginAsync("riverdale.admin");
        var name = "PG " + Guid.NewGuid().ToString("N")[..8];
        var examId = (long)JObject.Parse(await (await admin.PostAsJsonAsync("/api/exams",
            new { Name = name, ExamType = "Term Exam", ClassIds = new[] { ClassId } })).Content.ReadAsStringAsync())["data"]!["exam_id"]!;
        var math = await SubjectIdAsync(admin, "MATH");
        await admin.PostAsJsonAsync("/api/exams/class-subjects", new
        {
            ExamId = examId, ClassId = ClassId,
            Subjects = new[] { new { SubjectId = math, MaxMarks = 100, PassMarks = 33, SubjectType = "Theory" } }
        });
        // Intentionally enter NO marks -> every student missing.

        // Publish without force -> 400 (missing-marks guard).
        var blocked = await admin.PostAsJsonAsync("/api/exams/publish", new { ExamId = examId, Publish = true });
        Assert.Equal(HttpStatusCode.BadRequest, blocked.StatusCode);

        // Publish with force -> OK.
        var forced = await admin.PostAsJsonAsync("/api/exams/publish", new { ExamId = examId, Publish = true, Force = true });
        Assert.Equal(HttpStatusCode.OK, forced.StatusCode);
    }

    [Fact]
    public async Task Marks_entry_resolve_sheet_template_and_import_preview()
    {
        if (NoDb) return;
        var admin = await _fx.LoginAsync("riverdale.admin");
        var name = "ME " + Guid.NewGuid().ToString("N")[..8];
        var examId = (long)JObject.Parse(await (await admin.PostAsJsonAsync("/api/exams",
            new { Name = name, ExamType = "Term Exam", ClassIds = new[] { 1L } })).Content.ReadAsStringAsync())["data"]!["exam_id"]!;
        var math = await SubjectIdAsync(admin, "MATH");
        await admin.PostAsJsonAsync("/api/exams/class-subjects", new
        {
            ExamId = examId, ClassId = 1L,
            Subjects = new[] { new { SubjectId = math, MaxMarks = 100, PassMarks = 33, SubjectType = "Theory" } }
        });

        // Subjects-for-class dropdown.
        var subs = JObject.Parse(await (await admin.GetAsync($"/api/exams/{examId}/classes/1/subjects")).Content.ReadAsStringAsync());
        var subItems = (JArray)subs["data"]!["items"]!;
        Assert.Single(subItems);
        var examSubjectId = (long)subItems[0]!["exam_subject_id"]!;

        // Resolve (exam,class,subject) -> exam_subject.
        var resolve = JObject.Parse(await (await admin.GetAsync($"/api/exams/{examId}/classes/1/subjects/{math}/resolve")).Content.ReadAsStringAsync());
        Assert.Equal(examSubjectId, (long)resolve["data"]!["exam_subject_id"]!);

        // Sheet roster includes Ava (student 1) and exposes roll_number + entered flag.
        var sheet = JObject.Parse(await (await admin.GetAsync($"/api/exams/subjects/{examSubjectId}/sheet")).Content.ReadAsStringAsync());
        var roster = (JArray)sheet["data"]!["items"]!;
        Assert.Contains(roster, i => (long)i["student_id"]! == StudentId);
        Assert.True(roster[0]!["entered"] is not null);

        // Excel template downloads as an xlsx.
        var tpl = await admin.GetAsync($"/api/exams/subjects/{examSubjectId}/template");
        Assert.Equal(HttpStatusCode.OK, tpl.StatusCode);
        Assert.Contains("spreadsheetml", tpl.Content.Headers.ContentType!.MediaType);
        var tplBytes = await tpl.Content.ReadAsByteArrayAsync();
        Assert.True(tplBytes.Length > 0);

        // Round-trip: upload the downloaded template -> import preview parses rows.
        using var form = new MultipartFormDataContent();
        var fileContent = new ByteArrayContent(tplBytes);
        fileContent.Headers.ContentType = new System.Net.Http.Headers.MediaTypeHeaderValue(
            "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet");
        form.Add(fileContent, "file", "marks.xlsx");
        var import = await admin.PostAsync($"/api/exams/subjects/{examSubjectId}/import", form);
        Assert.Equal(HttpStatusCode.OK, import.StatusCode);
        var preview = JObject.Parse(await import.Content.ReadAsStringAsync())["data"]!;
        Assert.True((int)preview["valid"]! >= 1);
    }

    [Fact]
    public async Task Resolve_unconfigured_subject_is_404()
    {
        if (NoDb) return;
        var admin = await _fx.LoginAsync("riverdale.admin");
        var examId = (long)JObject.Parse(await (await admin.PostAsJsonAsync("/api/exams",
            new { Name = "RU " + Guid.NewGuid().ToString("N")[..8], ClassIds = new[] { 1L } })).Content.ReadAsStringAsync())["data"]!["exam_id"]!;
        var eng = await SubjectIdAsync(admin, "ENG"); // not configured for this exam
        var resp = await admin.GetAsync($"/api/exams/{examId}/classes/1/subjects/{eng}/resolve");
        Assert.Equal(HttpStatusCode.NotFound, resp.StatusCode);
    }

    [Fact]
    public async Task Class_subjects_and_schedule_configure_flow()
    {
        if (NoDb) return;
        var admin = await _fx.LoginAsync("riverdale.admin");
        var name = "CS " + Guid.NewGuid().ToString("N")[..8];
        var examId = (long)JObject.Parse(await (await admin.PostAsJsonAsync("/api/exams",
            new { Name = name, ExamType = "Term Exam", ClassIds = new[] { 1L } })).Content.ReadAsStringAsync())["data"]!["exam_id"]!;

        var math = await SubjectIdAsync(admin, "MATH");
        var sci = await SubjectIdAsync(admin, "SCI");

        // Save two subjects for class 1 (one Theory, one Practical).
        var save = await admin.PostAsJsonAsync("/api/exams/class-subjects", new
        {
            ExamId = examId,
            ClassId = 1L,
            Subjects = new[]
            {
                new { SubjectId = math, MaxMarks = 100, PassMarks = 33, SubjectType = "Theory" },
                new { SubjectId = sci, MaxMarks = 50, PassMarks = 20, SubjectType = "Practical" }
            }
        });
        Assert.Equal(HttpStatusCode.OK, save.StatusCode);
        Assert.Equal(2, (int)JObject.Parse(await save.Content.ReadAsStringAsync())["data"]!["count"]!);

        // List returns both with type.
        var list = JObject.Parse(await (await admin.GetAsync($"/api/exams/{examId}/class-subjects?classId=1")).Content.ReadAsStringAsync());
        var items = (JArray)list["data"]!["items"]!;
        Assert.Equal(2, items.Count);
        Assert.Contains(items, i => i["subject_type"]!.ToString() == "Practical");

        // Schedule one of them.
        var examSubjectId = (long)items[0]!["exam_subject_id"]!;
        var sched = await admin.PostAsJsonAsync("/api/exams/schedule", new
        {
            ExamId = examId,
            Items = new[] { new { ExamSubjectId = examSubjectId, ExamDate = "2026-12-01", StartTime = "09:00", EndTime = "11:00", Room = "Room 101" } }
        });
        Assert.Equal(HttpStatusCode.OK, sched.StatusCode);

        var schedList = JObject.Parse(await (await admin.GetAsync($"/api/exams/{examId}/schedule?classId=1")).Content.ReadAsStringAsync());
        var schedItems = (JArray)schedList["data"]!["items"]!;
        Assert.Contains(schedItems, i => i["room"]?.ToString() == "Room 101");

        // Re-save with only one subject -> the other is removed.
        var resave = await admin.PostAsJsonAsync("/api/exams/class-subjects", new
        {
            ExamId = examId,
            ClassId = 1L,
            Subjects = new[] { new { SubjectId = math, MaxMarks = 100, PassMarks = 33, SubjectType = "Theory" } }
        });
        Assert.Equal(HttpStatusCode.OK, resave.StatusCode);
        var after = JObject.Parse(await (await admin.GetAsync($"/api/exams/{examId}/class-subjects?classId=1")).Content.ReadAsStringAsync());
        Assert.Single((JArray)after["data"]!["items"]!);
    }

    [Fact]
    public async Task Teacher_cannot_save_class_subjects_403()
    {
        if (NoDb) return;
        var admin = await _fx.LoginAsync("riverdale.admin");
        var examId = (long)JObject.Parse(await (await admin.PostAsJsonAsync("/api/exams",
            new { Name = "CSG " + Guid.NewGuid().ToString("N")[..8], ClassIds = new[] { 1L } })).Content.ReadAsStringAsync())["data"]!["exam_id"]!;
        var math = await SubjectIdAsync(admin, "MATH");

        var teacher = await _fx.LoginAsync("riverdale.teacher"); // no exam.manage
        var resp = await teacher.PostAsJsonAsync("/api/exams/class-subjects", new
        {
            ExamId = examId, ClassId = 1L,
            Subjects = new[] { new { SubjectId = math, MaxMarks = 100, PassMarks = 33, SubjectType = "Theory" } }
        });
        Assert.Equal(HttpStatusCode.Forbidden, resp.StatusCode);
    }

    [Fact]
    public async Task Multi_class_exam_lists_with_classes_and_derived_status()
    {
        if (NoDb) return;
        var admin = await _fx.LoginAsync("riverdale.admin");
        var name = "HY " + Guid.NewGuid().ToString("N")[..8];
        // Two classes (1 and 2), future dates -> Upcoming.
        var examId = (long)JObject.Parse(await (await admin.PostAsJsonAsync("/api/exams", new
        {
            Name = name,
            ExamType = "Term Exam",
            ClassIds = new[] { 1L, 2L },
            StartDate = DateTime.Today.AddDays(10).ToString("yyyy-MM-dd"),
            EndDate = DateTime.Today.AddDays(20).ToString("yyyy-MM-dd")
        })).Content.ReadAsStringAsync())["data"]!["exam_id"]!;

        // List with search finds it, shows 2 classes + status Upcoming.
        var list = JObject.Parse(await (await admin.GetAsync($"/api/exams?search={name}")).Content.ReadAsStringAsync());
        var items = (JArray)list["data"]!["items"]!;
        var row = items.First(i => (long)i["exam_id"]! == examId);
        Assert.Equal(2, (int)row["class_count"]!);
        Assert.Equal("Upcoming", row["status"]!.ToString());

        // Get returns class_ids for the wizard.
        var get = JObject.Parse(await (await admin.GetAsync($"/api/exams/{examId}")).Content.ReadAsStringAsync());
        var classIds = (JArray)get["data"]!["class_ids"]!;
        Assert.Equal(2, classIds.Count);

        // Status filter excludes a non-matching bucket.
        var completed = JObject.Parse(await (await admin.GetAsync($"/api/exams?search={name}&status=Completed")).Content.ReadAsStringAsync());
        Assert.Empty((JArray)completed["data"]!["items"]!);
    }
}
