/** Typed contracts mirroring the EduNestIO API DTOs. */

/** Consistent response envelope returned by every endpoint. */
export interface ApiResponse<T = unknown> {
  isSuccess: boolean;
  resultCode: number;
  resultCodeDescription: string | null;
  correlationId: string | null;
  data: T | null;
}

export interface StatusData {
  status: string;
  service: string;
  server_time_utc: string;
}

export interface LoginRequest {
  username: string;
  password: string;
}

export interface LoginResult {
  token: string;
  expiresAtUtc: string;
  userId: number;
  tenantId: number;
  username: string;
  email: string | null;
  fullName: string | null;
  tenantName: string | null;
  studentId: number | null;
  roles: string[];
  permissions: string[];
}

export interface CurrentUser {
  user_id: number;
  tenant_id: number;
  username: string;
  email: string | null;
  roles: string[];
  permissions: string[];
}

/** Student list-row read model (snake_case from the DB jsonb). */
export interface Student {
  student_id: number;
  tenant_id: number;
  admission_number: string;
  first_name: string;
  middle_name: string | null;
  last_name: string;
  gender: string | null;
  date_of_birth: string | null;
  email: string | null;
  phone: string | null;
  city: string | null;
  class_id: number | null;
  class_name: string | null;
  section_id: number | null;
  section_name: string | null;
  academic_year_id: number | null;
  roll_number: string | null;
  guardian_name: string | null;
  guardian_phone: string | null;
  admission_date: string | null;
  photo_url: string | null;
  status: string | null;
  status_reason: string | null;
  status_changed_at: string | null;
  created_at: string;
}

/** Full student profile (returned by GET /students/{id}). */
export interface StudentDetail extends Student {
  nationality: string | null;
  blood_group: string | null;
  address_line1: string | null;
  address_line2: string | null;
  state: string | null;
  postal_code: string | null;
  country: string | null;
  academic_year_name: string | null;
  guardian_relation: string | null;
  guardian_alt_phone: string | null;
  guardian_email: string | null;
  status_reason: string | null;
  status_changed_at: string | null;
  updated_at: string | null;
}

/** Student create/update request (VO, PascalCase to match the API model binder). */
export interface StudentUpsert {
  AdmissionNumber?: string;
  FirstName: string;
  MiddleName?: string | null;
  LastName: string;
  Gender?: string | null;
  DateOfBirth?: string | null;
  Nationality?: string | null;
  BloodGroup?: string | null;
  PhotoUrl?: string | null;
  Email?: string | null;
  Phone?: string | null;
  AddressLine1?: string | null;
  AddressLine2?: string | null;
  City?: string | null;
  State?: string | null;
  PostalCode?: string | null;
  Country?: string | null;
  ClassId?: number | null;
  SectionId?: number | null;
  AcademicYearId?: number | null;
  RollNumber?: string | null;
  AdmissionDate?: string | null;
  Status?: string | null;
  GuardianName?: string | null;
  GuardianRelation?: string | null;
  GuardianPhone?: string | null;
  GuardianAltPhone?: string | null;
  GuardianEmail?: string | null;
}

export interface StudentPage {
  items: Student[];
  page: number;
  page_size: number;
  total_count: number;
}

export interface StudentSummary {
  total: number;
  active: number;
  inactive: number;
  graduated: number;
  withdrawn: number;
  by_status: Record<string, number>;
}

export interface StudentStatusRequest {
  Status: string;
  Reason?: string | null;
}

/** One row of a student's per-class enrollment history. */
export interface Enrollment {
  enrollment_id: number;
  class_id: number | null;
  class_name: string | null;
  section_id: number | null;
  section_name: string | null;
  academic_year_id: number | null;
  academic_year_name: string | null;
  roll_number: string | null;
  status: string;
  from_date: string | null;
  to_date: string | null;
  note: string | null;
}

export interface PromoteRequest {
  StudentIds: number[];
  ToClassId: number;
  ToSectionId?: number | null;
  AcademicYearId?: number | null;
  Note?: string | null;
}
export interface GraduateRequest {
  StudentIds: number[];
  Note?: string | null;
}
export interface WithdrawRequest {
  StudentIds: number[];
  Reason?: string | null;
}

/** Query params for the student list. */
export interface StudentListQuery {
  search?: string;
  classId?: number;
  sectionId?: number;
  academicYearId?: number;
  status?: string;
  page?: number;
  pageSize?: number;
  sortBy?: string;
  sortDir?: string;
}

// ---- Academic Setup ----
export interface AcademicYear {
  academic_year_id: number;
  name: string;
  start_date: string;
  end_date: string;
  is_current: boolean;
}
export interface AcademicYearUpsert {
  AcademicYearId?: number | null;
  Name: string;
  StartDate: string;
  EndDate: string;
  IsCurrent: boolean;
}
export interface SchoolClass {
  class_id: number;
  name: string;
  ordinal: number;
  section_count: number;
  student_count: number;
}
export interface ClassUpsert {
  ClassId?: number | null;
  Name: string;
  Ordinal: number;
}
export interface Section {
  section_id: number;
  name: string;
  class_id: number;
  class_name: string;
}
export interface SectionUpsert {
  SectionId?: number | null;
  ClassId: number;
  Name: string;
}
export interface Subject {
  subject_id: number;
  name: string;
  code: string;
  is_active: boolean;
}
export interface SubjectUpsert {
  SubjectId?: number | null;
  Name: string;
  Code: string;
  IsActive: boolean;
}
export interface ItemsData<T> { items: T[]; }

// ---- Teachers (app_users with a teaching role) ----
export interface Teacher {
  user_id: number;
  full_name: string;
  username: string;
  email: string | null;
}

// ---- Timetable ----
export interface TimetableSlot {
  slot_id: number;
  class_id: number;
  class_name?: string | null;
  section_id: number | null;
  section_name?: string | null;
  day_of_week: number;      // 1=Mon .. 6=Sat
  period_no: number;
  start_time: string | null; // "HH:mm:ss" or null
  end_time: string | null;
  subject_id: number | null;
  subject_name: string | null;
  teacher_id: number | null;
  teacher_name: string | null;
  room: string | null;
}
export interface TimetableSlotUpsert {
  SlotId?: number | null;
  ClassId: number;
  SectionId?: number | null;
  DayOfWeek: number;
  PeriodNo: number;
  StartTime?: string | null;
  EndTime?: string | null;
  SubjectId?: number | null;
  TeacherId?: number | null;
  Room?: string | null;
}

// ---- Assignments ----
export interface Assignment {
  assignment_id: number;
  class_id: number;
  class_name?: string | null;
  section_id: number | null;
  section_name?: string | null;
  subject_id: number | null;
  subject_name: string | null;
  teacher_id: number | null;
  teacher_name: string | null;
  title: string;
  description: string | null;
  due_date: string | null;
  max_marks: number | null;
  created_at: string;
  submission_count?: number;
}
export interface AssignmentUpsert {
  AssignmentId?: number | null;
  ClassId: number;
  SectionId?: number | null;
  SubjectId?: number | null;
  TeacherId?: number | null;
  Title: string;
  Description?: string | null;
  DueDate?: string | null;
  MaxMarks?: number | null;
}
/** A student's view of an assignment (includes their own submission fields). */
export interface StudentAssignment {
  assignment_id: number;
  subject_name: string | null;
  teacher_name: string | null;
  title: string;
  description: string | null;
  due_date: string | null;
  max_marks: number | null;
  created_at: string;
  submission_id: number | null;
  my_content: string | null;
  my_status: 'Submitted' | 'Graded' | null;
  my_marks: number | null;
  my_feedback: string | null;
  my_submitted_at: string | null;
}
/** One row of the teacher's submission-review grid (one per student). */
export interface AssignmentSubmission {
  student_id: number;
  admission_number: string;
  roll_number: string | null;
  first_name: string;
  last_name: string;
  submission_id: number | null;
  content: string | null;
  status: 'Submitted' | 'Graded' | null;
  marks: number | null;
  feedback: string | null;
  submitted_at: string | null;
  graded_at: string | null;
}

// ---- Bulk student import ----
export interface StudentImportRow {
  RowNumber: number;
  Status: 'Valid' | 'Invalid';
  Error?: string | null;
  FirstName: string;
  MiddleName?: string | null;
  LastName: string;
  Gender?: string | null;
  DateOfBirth?: string | null;
  Nationality?: string | null;
  BloodGroup?: string | null;
  ClassName?: string | null;
  ClassId?: number | null;
  SectionName?: string | null;
  SectionId?: number | null;
  AcademicYear?: string | null;
  AcademicYearId?: number | null;
  RollNumber?: string | null;
  AdmissionDate?: string | null;
  GuardianName?: string | null;
  Relationship?: string | null;
  GuardianPhone?: string | null;
  GuardianEmail?: string | null;
  Email?: string | null;
  Phone?: string | null;
  AddressLine1?: string | null;
  City?: string | null;
  State?: string | null;
  PostalCode?: string | null;
  Country?: string | null;
}
export interface StudentImportPreview {
  Rows: StudentImportRow[];
  Valid: number;
  Invalid: number;
}
export interface StudentImportResult {
  created: number;
  failed: number;
  errors: string[];
}

// ---- Leave management ----
export interface LeaveRequest {
  leave_id: number;
  student_id: number;
  admission_number?: string;
  first_name?: string;
  last_name?: string;
  class_name?: string | null;
  section_name?: string | null;
  from_date: string;
  to_date: string;
  leave_type: string | null;
  reason: string;
  status: 'Pending' | 'Approved' | 'Rejected' | 'Cancelled';
  decided_at: string | null;
  decision_note: string | null;
  created_at: string;
}
export interface LeaveApplyRequest {
  StudentId?: number | null;
  FromDate: string;
  ToDate: string;
  LeaveType?: string | null;
  Reason: string;
}
export interface LeaveDecisionRequest {
  Decision: 'Approved' | 'Rejected';
  Note?: string | null;
}

// ---- Admissions ----
export interface Enquiry {
  enquiry_id: number;
  enquiry_number: string;
  applicant_name: string;
  guardian_name: string | null;
  phone: string | null;
  email: string | null;
  source: string | null;
  stage: string;
  desired_class_id: number | null;
  desired_class_name: string | null;
  next_followup_at: string | null;
  converted_student_id: number | null;
  created_at: string;
}
export interface EnquiryUpsert {
  EnquiryId?: number | null;
  ApplicantName: string;
  GuardianName?: string | null;
  Phone?: string | null;
  Email?: string | null;
  Source?: string | null;
  DesiredClassId?: number | null;
  Stage?: string | null;
  Notes?: string | null;
}
export interface EnquiryPage {
  items: Enquiry[];
  page: number;
  page_size: number;
  total_count: number;
}
export interface Followup {
  followup_id: number;
  note: string;
  outcome: string | null;
  created_at: string;
}

// ---- Attendance ----
export type AttendanceStatus = 'Present' | 'Absent' | 'Late' | 'Leave';
export interface AttendanceSheetRow {
  student_id: number;
  admission_number: string;
  roll_number?: string | null;
  first_name: string;
  last_name: string;
  status: AttendanceStatus;
  remark: string | null;
  marked: boolean;
  /** True when the student has an approved leave covering this date (row is locked to Leave). */
  on_leave?: boolean;
}
export interface AttendanceSheet {
  class_id: number;
  section_id: number | null;
  subject_id: number | null;
  attend_date: string;
  items: AttendanceSheetRow[];
}
export interface AttendanceMarkRequest {
  ClassId: number;
  SectionId?: number | null;
  SubjectId?: number | null;
  AttendDate: string;
  Entries: { StudentId: number; Status: AttendanceStatus; Remark?: string | null }[];
}

/** Per-school settings (incl. how attendance is taken). */
export interface TenantSettings {
  tenant_id: number;
  name: string;
  code: string;
  attendance_mode: 'Daily' | 'Subject';
  locale: string;
  time_zone: string;
  currency_code: string;
}
export interface AttendanceTodaySummary {
  attend_date: string;
  active_students: number;
  by_status: Record<string, number>;
}
/** One day of a student's attendance history. */
export interface AttendanceHistoryRow {
  attend_date: string;
  status: AttendanceStatus;
  remark: string | null;
}

// ---- Fees & Finance ----
export interface FeeHead { fee_head_id: number; name: string; code: string; is_active: boolean; }
export interface FeeHeadUpsert { FeeHeadId?: number | null; Name: string; Code: string; IsActive: boolean; }
export interface FeeLedgerLine {
  fee_assignment_id: number;
  fee_head_name: string;
  amount: number;
  discount: number;
  paid: number;
  balance: number;
  due_date: string | null;
  status: string;
}
export interface FeeLedger {
  items: FeeLedgerLine[];
  net_total: number;
  paid_total: number;
  balance: number;
}
export interface FeeAssignRequest { StudentId: number; FeeHeadId: number; Amount: number; Discount: number; DueDate?: string | null; Note?: string | null; }
export interface PaymentRequest { StudentId: number; Amount: number; Mode: string; Reference?: string | null; }
export interface Defaulter { student_id: number; admission_number: string; first_name: string; last_name: string; class_name: string | null; balance: number; }
export interface CollectionReport { from: string; to: string; total_collected: number; payment_count: number; by_mode: Record<string, number>; }

// ---- Exams & Report Cards ----
export interface ExamClassRef {
  class_id: number;
  name: string;
}
export interface Exam {
  exam_id: number;
  name: string;
  exam_type: string | null;
  academic_year_id: number | null;
  academic_year_name: string | null;
  start_date: string | null;
  end_date: string | null;
  description: string | null;
  is_published: boolean;
  classes: ExamClassRef[];
  class_count: number;
  status: 'Upcoming' | 'Ongoing' | 'Completed' | 'Published';
}
export interface ExamDetail extends Exam {
  class_ids: number[];
}
export interface ExamUpsert {
  ExamId?: number | null;
  Name: string;
  ExamType?: string | null;
  AcademicYearId?: number | null;
  StartDate?: string | null;
  EndDate?: string | null;
  Description?: string | null;
  ClassIds: number[];
}
export interface ExamListQuery {
  search?: string;
  classId?: number;
  academicYearId?: number;
  status?: string;
  examType?: string;
}

/** A subject row within one class of an exam. */
export interface ExamSubjectRow {
  exam_subject_id?: number;
  class_id?: number | null;
  class_name?: string | null;
  subject_id: number;
  subject_name?: string | null;
  subject_code?: string | null;
  max_marks: number;
  pass_marks: number;
  subject_type: string;
}
export interface ExamClassSubjectsRequest {
  ExamId: number;
  ClassId: number;
  Subjects: {
    ExamSubjectId?: number | null;
    SubjectId: number;
    MaxMarks: number;
    PassMarks: number;
    SubjectType: string;
  }[];
}
/** A schedule row (joined with its subject). */
export interface ExamScheduleRow {
  exam_subject_id: number;
  class_id: number | null;
  class_name: string | null;
  subject_name: string;
  subject_code: string;
  subject_type: string;
  exam_date: string | null;
  start_time: string | null;
  end_time: string | null;
  room: string | null;
}
export interface ExamScheduleSaveRequest {
  ExamId: number;
  Items: {
    ExamSubjectId: number;
    ExamDate?: string | null;
    StartTime?: string | null;
    EndTime?: string | null;
    Room?: string | null;
  }[];
}
export interface ExamSubjectAdd {
  ExamId: number;
  SubjectId: number;
  MaxMarks: number;
  PassMarks: number;
}
export interface ExamMarksSheetRow {
  student_id: number;
  admission_number: string;
  roll_number: string | null;
  first_name: string;
  last_name: string;
  marks: number | null;
  is_absent: boolean;
  entered: boolean;
}
export interface ExamMarksSheet {
  exam_subject_id: number;
  max_marks: number;
  items: ExamMarksSheetRow[];
}
export interface ExamMarksSaveRequest {
  ExamSubjectId: number;
  Entries: { StudentId: number; Marks: number | null; IsAbsent: boolean }[];
}
/** A subject option for the marks-entry dropdown. */
export interface ExamSubjectOption {
  exam_subject_id: number;
  subject_id: number;
  subject_name: string;
  subject_code: string;
  max_marks: number;
  pass_marks: number;
  subject_type: string;
}
/** One parsed row from an Excel import preview. */
export interface ImportPreviewRow {
  student_id: number;
  admission_number: string;
  name: string;
  marks: number | null;
  is_absent: boolean;
  status: 'Valid' | 'Invalid' | 'Unknown';
  error: string | null;
}
export interface ImportPreview {
  rows: ImportPreviewRow[];
  valid: number;
  invalid: number;
}

/** One row of the class-wide result preview. */
export interface ResultPreviewRow {
  student_id: number;
  admission_number: string;
  roll_number: string | null;
  first_name: string;
  last_name: string;
  obtained: number;
  max_total: number;
  percentage: number;
  grade: string | null;
  result: string;
  status: 'Ready' | 'Missing';
  /** Subjects that still have no marks (comma-joined names), null when none. */
  missing_subjects: string | null;
  /** How many subjects are still unmarked for this student. */
  missing_count: number;
}
export interface ResultPreview {
  exam_id: number;
  class_id: number;
  subject_count: number;
  total_students: number;
  completed: number;
  missing: number;
  ready_to_publish: boolean;
  items: ResultPreviewRow[];
}
export interface ReportCardSubject {
  subject_name: string;
  subject_type: string;
  max_marks: number;
  pass_marks: number;
  marks: number | null;
  is_absent: boolean;
  passed: boolean;
}
export interface ReportCardStudent {
  student_id: number;
  admission_number: string;
  roll_number: string | null;
  first_name: string;
  last_name: string;
  photo_url: string | null;
  class_name: string | null;
  section_name: string | null;
}
export interface ReportCardExam {
  exam_id: number;
  exam_name: string;
  exam_type: string | null;
  academic_year_name: string | null;
  school_name: string;
}
export interface ReportCard {
  exam_id: number;
  student_id: number;
  is_published: boolean;
  student: ReportCardStudent;
  exam: ReportCardExam;
  subjects: ReportCardSubject[];
  obtained: number;
  max_total: number;
  percentage: number;
  grade: string;
  result: string;
}

/** One row of the class-wise report-card list. */
export interface ReportCardListRow {
  student_id: number;
  admission_number: string;
  roll_number: string | null;
  first_name: string;
  last_name: string;
  obtained: number;
  max_total: number;
  percentage: number;
  grade: string | null;
  result: string;
}
export interface ReportCardList {
  exam_id: number;
  class_id: number;
  is_published: boolean;
  items: ReportCardListRow[];
}
