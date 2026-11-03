using ClosedXML.Excel;

namespace EduNestIO.WebServices.RestAPI.Services;

/// <summary>
/// Builds the bulk-student-import Excel template and parses an uploaded sheet back
/// into raw rows. The template uses in-cell dropdowns (data validation) for Gender,
/// Blood Group, Class, Section and Academic Year — sourced from the school's own
/// data — so staff pick values instead of typing them. Name→id resolution and
/// validation happen in the controller/BL.
/// </summary>
public static class StudentImportExcel
{
    /// <summary>The ordered import columns. Header text in the template + parse order.</summary>
    public static readonly string[] Columns =
    {
        "First Name*", "Middle Name", "Last Name*", "Gender", "Date of Birth (YYYY-MM-DD)",
        "Nationality", "Blood Group", "Class", "Section", "Academic Year", "Roll Number",
        "Admission Date (YYYY-MM-DD)", "Guardian Name", "Relationship", "Guardian Phone",
        "Guardian Email", "Student Email", "Student Phone", "Address Line 1", "City",
        "State", "PIN Code", "Country"
    };

    // 1-based column indexes that get dropdowns.
    private const int ColGender = 4, ColBlood = 7, ColClass = 8, ColSection = 9, ColYear = 10, ColRelation = 14;
    private const int DataRows = 300; // how many rows get dropdowns / are importable

    // Layout: row 1 = title banner, row 2 = header, row 3+ = data.
    private const int HeaderRow = 2;
    private const int DataStartRow = 3;

    /// <summary>1-based column indexes that are mandatory (shown in a darker header).</summary>
    private static readonly HashSet<int> RequiredCols = new() { 1, 3 }; // First Name, Last Name

    /// <summary>One raw row read from the sheet (values as typed/picked by the user).</summary>
    public sealed class RawRow
    {
        public int RowNumber { get; set; }
        public string FirstName = "", MiddleName = "", LastName = "", Gender = "", DateOfBirth = "";
        public string Nationality = "", BloodGroup = "", ClassName = "", SectionName = "", AcademicYear = "";
        public string RollNumber = "", AdmissionDate = "", GuardianName = "", Relationship = "";
        public string GuardianPhone = "", GuardianEmail = "", Email = "", Phone = "";
        public string AddressLine1 = "", City = "", State = "", PostalCode = "", Country = "";

        public bool IsEmpty =>
            string.IsNullOrWhiteSpace(FirstName) && string.IsNullOrWhiteSpace(LastName) &&
            string.IsNullOrWhiteSpace(MiddleName) && string.IsNullOrWhiteSpace(ClassName) &&
            string.IsNullOrWhiteSpace(RollNumber) && string.IsNullOrWhiteSpace(GuardianName);
    }

    /// <summary>
    /// Workbook with a styled header, a hidden "Lists" sheet holding dropdown sources,
    /// and in-cell data-validation dropdowns on the choice columns. No sample data row.
    /// </summary>
    public static byte[] BuildTemplate(
        IReadOnlyList<string> genders, IReadOnlyList<string> bloodGroups,
        IReadOnlyList<string> classes, IReadOnlyList<string> sections,
        IReadOnlyList<string> years, IReadOnlyList<string> relationships)
    {
        using var wb = new XLWorkbook();
        wb.Style.Font.FontName = "Calibri";
        var ws = wb.Worksheets.Add("Students");
        var lastCol = Columns.Length;

        // Brand palette.
        var green = XLColor.FromHtml("#16a34a");
        var greenDark = XLColor.FromHtml("#0f5132");
        var slate = XLColor.FromHtml("#334155");
        var stripe = XLColor.FromHtml("#f3f8f4");
        var line = XLColor.FromHtml("#d7dce3");

        // --- hidden Lists sheet with one column per dropdown source ---
        var lists = wb.Worksheets.Add("Lists");
        WriteList(lists, 1, genders);        // A
        WriteList(lists, 2, bloodGroups);    // B
        WriteList(lists, 3, classes);        // C
        WriteList(lists, 4, sections);       // D
        WriteList(lists, 5, years);          // E
        WriteList(lists, 6, relationships);  // F
        lists.Hide();

        // --- row 1: title banner (merged across all columns) ---
        var banner = ws.Range(1, 1, 1, lastCol).Merge();
        banner.Value = "EduNestIO  ·  Student Import";
        banner.Style.Font.Bold = true;
        banner.Style.Font.FontSize = 15;
        banner.Style.Font.FontColor = XLColor.White;
        banner.Style.Fill.BackgroundColor = greenDark;
        banner.Style.Alignment.Vertical = XLAlignmentVerticalValues.Center;
        banner.Style.Alignment.Indent = 1;
        ws.Row(1).Height = 34;

        // --- row 2: header ---
        for (var c = 0; c < lastCol; c++)
        {
            var cell = ws.Cell(HeaderRow, c + 1);
            cell.Value = Columns[c];
            cell.Style.Font.Bold = true;
            cell.Style.Font.FontColor = XLColor.White;
            cell.Style.Fill.BackgroundColor = RequiredCols.Contains(c + 1) ? greenDark : slate;
            cell.Style.Alignment.Vertical = XLAlignmentVerticalValues.Center;
            cell.Style.Alignment.WrapText = true;
            cell.Style.Border.OutsideBorder = XLBorderStyleValues.Thin;
            cell.Style.Border.OutsideBorderColor = XLColor.White;
        }
        ws.Row(HeaderRow).Height = 30;

        // --- data rows: zebra striping + light borders + comfortable height ---
        var dataEnd = DataStartRow + DataRows - 1;
        for (var r = DataStartRow; r <= dataEnd; r++)
        {
            ws.Row(r).Height = 20;
            var rng = ws.Range(r, 1, r, lastCol);
            rng.Style.Border.OutsideBorder = XLBorderStyleValues.Thin;
            rng.Style.Border.InsideBorder = XLBorderStyleValues.Thin;
            rng.Style.Border.OutsideBorderColor = line;
            rng.Style.Border.InsideBorderColor = line;
            rng.Style.Alignment.Vertical = XLAlignmentVerticalValues.Center;
            if ((r - DataStartRow) % 2 == 1) rng.Style.Fill.BackgroundColor = stripe;
        }

        // Freeze the banner + header so columns stay visible while scrolling.
        ws.SheetView.FreezeRows(HeaderRow);

        // --- dropdowns on the choice columns ---
        AddDropdown(ws, ColGender, "Lists", "A", genders.Count);
        AddDropdown(ws, ColBlood, "Lists", "B", bloodGroups.Count);
        AddDropdown(ws, ColClass, "Lists", "C", classes.Count);
        AddDropdown(ws, ColSection, "Lists", "D", sections.Count);
        AddDropdown(ws, ColYear, "Lists", "E", years.Count);
        AddDropdown(ws, ColRelation, "Lists", "F", relationships.Count);

        // Sensible, readable column widths (date/email/address a bit wider).
        for (var c = 1; c <= lastCol; c++)
        {
            var header = Columns[c - 1];
            double w = 15;
            if (header.Contains("Date")) w = 22;
            else if (header.Contains("Email")) w = 26;
            else if (header.Contains("Address")) w = 26;
            else if (header.Contains("Name")) w = 18;
            else if (header is "Class" or "Section" or "Gender" or "PIN Code") w = 12;
            ws.Column(c).Width = w;
        }

        // --- instructions sheet (styled) ---
        var notes = wb.Worksheets.Add("Instructions");
        notes.Cell(1, 1).Value = "How to fill this template";
        notes.Cell(1, 1).Style.Font.Bold = true;
        notes.Cell(1, 1).Style.Font.FontSize = 14;
        notes.Cell(1, 1).Style.Font.FontColor = greenDark;
        var steps = new[]
        {
            "1.  Enter one student per row on the 'Students' sheet (start at row 3).",
            "2.  First Name and Last Name are required — their headers are dark green.",
            "3.  Gender, Blood Group, Class, Section, Academic Year and Relationship are",
            "     dropdowns: click the cell and pick from the list (no typing needed).",
            "4.  Dates use the format YYYY-MM-DD, e.g. 2015-06-12.",
            "5.  Section must belong to the chosen Class. Leave academic fields blank if",
            "     you are not assigning the class/section yet.",
            "6.  Admission number is generated automatically — there is no column for it.",
            "7.  Save the file as .xlsx and upload it on the Students page using 'Import'."
        };
        var r0 = 3;
        for (var i = 0; i < steps.Length; i++)
        {
            var cell = notes.Cell(r0 + i, 1);
            cell.Value = steps[i];
            cell.Style.Font.FontSize = 11;
            cell.Style.Font.FontColor = slate;
        }
        notes.Column(1).Width = 95;

        using var ms = new MemoryStream();
        wb.SaveAs(ms);
        return ms.ToArray();
    }

    private static void WriteList(IXLWorksheet lists, int col, IReadOnlyList<string> values)
    {
        for (var i = 0; i < values.Count; i++) lists.Cell(i + 1, col).Value = values[i];
    }

    /// <summary>Attach a dropdown (list validation) to a data column, sourced from a Lists column.</summary>
    private static void AddDropdown(IXLWorksheet ws, int col, string listSheet, string listCol, int count)
    {
        if (count <= 0) return; // nothing to choose from -> leave it a free-text cell
        var colLetter = ws.Column(col).ColumnLetter();
        var endRow = DataStartRow + DataRows - 1;
        var target = ws.Range($"{colLetter}{DataStartRow}:{colLetter}{endRow}");
        var source = $"'{listSheet}'!${listCol}$1:${listCol}${count}";
        var dv = target.CreateDataValidation();
        dv.List(source, true);          // in-cell dropdown
        dv.IgnoreBlanks = true;
        dv.ErrorStyle = XLErrorStyle.Warning; // warn (not hard block) so odd values still allowed
    }

    /// <summary>Read the uploaded workbook into raw rows (header skipped, empty rows dropped).</summary>
    public static List<RawRow> Parse(byte[] bytes)
    {
        var rows = new List<RawRow>();
        using var ms = new MemoryStream(bytes);
        using var wb = new XLWorkbook(ms);
        var ws = wb.Worksheets.FirstOrDefault(w => w.Name.Equals("Students", StringComparison.OrdinalIgnoreCase))
                 ?? wb.Worksheets.First();

        string Cell(IXLRow row, int col) => row.Cell(col).GetString().Trim();

        var lastRow = ws.LastRowUsed()?.RowNumber() ?? 1;
        for (var r = DataStartRow; r <= lastRow; r++)
        {
            var row = ws.Row(r);
            var raw = new RawRow
            {
                RowNumber = r,
                FirstName = Cell(row, 1), MiddleName = Cell(row, 2), LastName = Cell(row, 3),
                Gender = Cell(row, 4), DateOfBirth = Cell(row, 5), Nationality = Cell(row, 6),
                BloodGroup = Cell(row, 7), ClassName = Cell(row, 8), SectionName = Cell(row, 9),
                AcademicYear = Cell(row, 10), RollNumber = Cell(row, 11), AdmissionDate = Cell(row, 12),
                GuardianName = Cell(row, 13), Relationship = Cell(row, 14), GuardianPhone = Cell(row, 15),
                GuardianEmail = Cell(row, 16), Email = Cell(row, 17), Phone = Cell(row, 18),
                AddressLine1 = Cell(row, 19), City = Cell(row, 20), State = Cell(row, 21),
                PostalCode = Cell(row, 22), Country = Cell(row, 23)
            };
            if (!raw.IsEmpty) rows.Add(raw);
        }
        return rows;
    }
}
