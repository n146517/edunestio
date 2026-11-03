using ClosedXML.Excel;
using Newtonsoft.Json.Linq;

namespace EduNestIO.WebServices.RestAPI.Services;

/// <summary>
/// Builds the Excel marks template and parses an uploaded sheet back into marks
/// entries, matching students by admission number against the live roster. The
/// parser only produces a preview; persistence happens via the marks save endpoint.
/// </summary>
public static class ExamMarksExcel
{
    /// <summary>A single roster row extracted from the marks sheet jsonb.</summary>
    public sealed record RosterRow(long StudentId, string AdmissionNumber, string? RollNumber,
                                   string Name, decimal? Marks, bool IsAbsent);

    public static decimal MaxMarks(JToken? data) => data?["max_marks"]?.Value<decimal?>() ?? 100m;

    public static List<RosterRow> RosterRows(JToken? data)
    {
        var list = new List<RosterRow>();
        if (data?["items"] is not JArray items) return list;
        foreach (var i in items)
        {
            list.Add(new RosterRow(
                i["student_id"]!.Value<long>(),
                i["admission_number"]?.Value<string>() ?? "",
                i["roll_number"]?.Value<string>(),
                $"{i["first_name"]?.Value<string>()} {i["last_name"]?.Value<string>()}".Trim(),
                i["marks"]?.Type == JTokenType.Null ? null : i["marks"]?.Value<decimal?>(),
                i["is_absent"]?.Value<bool>() ?? false));
        }
        return list;
    }

    /// <summary>Workbook with a header + one row per student (Adm No, Roll, Name, Marks).</summary>
    public static byte[] BuildTemplate(List<RosterRow> rows, decimal maxMarks)
    {
        using var wb = new XLWorkbook();
        var ws = wb.Worksheets.Add("Marks");

        ws.Cell(1, 1).Value = "Admission No";
        ws.Cell(1, 2).Value = "Roll No";
        ws.Cell(1, 3).Value = "Student Name";
        ws.Cell(1, 4).Value = $"Marks (max {maxMarks})";
        ws.Cell(1, 5).Value = "Absent (Y/N)";
        ws.Range(1, 1, 1, 5).Style.Font.Bold = true;
        ws.Range(1, 1, 1, 5).Style.Fill.BackgroundColor = XLColor.FromHtml("#0f5132");
        ws.Range(1, 1, 1, 5).Style.Font.FontColor = XLColor.White;

        var r = 2;
        foreach (var row in rows)
        {
            ws.Cell(r, 1).Value = row.AdmissionNumber;
            ws.Cell(r, 2).Value = row.RollNumber ?? "";
            ws.Cell(r, 3).Value = row.Name;
            if (row.Marks.HasValue) ws.Cell(r, 4).Value = row.Marks.Value;
            ws.Cell(r, 5).Value = row.IsAbsent ? "Y" : "";
            // Admission No / Roll / Name are reference columns — lock from editing.
            ws.Range(r, 1, r, 3).Style.Fill.BackgroundColor = XLColor.FromHtml("#f3f6f4");
            r++;
        }
        ws.Columns().AdjustToContents();
        using var ms = new MemoryStream();
        wb.SaveAs(ms);
        return ms.ToArray();
    }

    /// <summary>One parsed/validated preview row for the import review screen.</summary>
    public sealed class PreviewRow
    {
        public long student_id { get; set; }
        public string admission_number { get; set; } = "";
        public string name { get; set; } = "";
        public decimal? marks { get; set; }
        public bool is_absent { get; set; }
        public string status { get; set; } = "";   // Valid | Invalid | Unknown
        public string? error { get; set; }
    }

    public sealed class ImportPreview
    {
        public List<PreviewRow> rows { get; set; } = new();
        public int valid { get; set; }
        public int invalid { get; set; }
    }

    /// <summary>Parse the uploaded workbook and validate against the roster + max marks.</summary>
    public static ImportPreview Parse(byte[] bytes, JToken? sheetData, decimal maxMarks)
    {
        var roster = RosterRows(sheetData);
        var byAdm = roster
            .GroupBy(x => x.AdmissionNumber.Trim(), StringComparer.OrdinalIgnoreCase)
            .ToDictionary(g => g.Key, g => g.First(), StringComparer.OrdinalIgnoreCase);

        var preview = new ImportPreview();
        using var ms = new MemoryStream(bytes);
        using var wb = new XLWorkbook(ms);
        var ws = wb.Worksheets.First();

        // Skip the header row; read until the first fully empty row.
        var lastRow = ws.LastRowUsed()?.RowNumber() ?? 1;
        for (var r = 2; r <= lastRow; r++)
        {
            var adm = ws.Cell(r, 1).GetString().Trim();
            if (string.IsNullOrWhiteSpace(adm)) continue;

            var pr = new PreviewRow { admission_number = adm };

            var marksCell = ws.Cell(r, 4).GetString().Trim();
            var absentCell = ws.Cell(r, 5).GetString().Trim();
            pr.is_absent = absentCell.Equals("Y", StringComparison.OrdinalIgnoreCase)
                           || absentCell.Equals("Yes", StringComparison.OrdinalIgnoreCase);

            if (!byAdm.TryGetValue(adm, out var rosterRow))
            {
                pr.status = "Unknown";
                pr.error = "No student with this admission number in the roster.";
                preview.invalid++;
                preview.rows.Add(pr);
                continue;
            }

            pr.student_id = rosterRow.StudentId;
            pr.name = rosterRow.Name;

            if (pr.is_absent)
            {
                pr.marks = null;
                pr.status = "Valid";
                preview.valid++;
            }
            else if (string.IsNullOrWhiteSpace(marksCell))
            {
                pr.marks = null;
                pr.status = "Valid"; // blank = not entered yet, allowed
                preview.valid++;
            }
            else if (decimal.TryParse(marksCell, out var m) && m >= 0 && m <= maxMarks)
            {
                pr.marks = m;
                pr.status = "Valid";
                preview.valid++;
            }
            else
            {
                pr.status = "Invalid";
                pr.error = $"Marks must be a number between 0 and {maxMarks}.";
                preview.invalid++;
            }
            preview.rows.Add(pr);
        }
        return preview;
    }
}
