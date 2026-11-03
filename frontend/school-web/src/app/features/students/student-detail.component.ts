import { Component, computed, inject, signal } from '@angular/core';
import { ActivatedRoute, Router, RouterLink } from '@angular/router';
import { DatePipe, DecimalPipe } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { StudentService } from '../../core/services/student.service';
import { AcademicService } from '../../core/services/academic.service';
import { ExamService } from '../../core/services/exam.service';
import { AttendanceService } from '../../core/services/attendance.service';
import { AuthStore } from '../../core/auth/auth.store';
import { NotificationService } from '../../core/services/notification.service';
import { AttendanceHistoryRow, Enrollment, SchoolClass, Section, StudentDetail, StudentUpsert } from '../../core/models/api.models';

type LoadState = 'loading' | 'success' | 'error';

type Tab =
  | 'overview'
  | 'personal'
  | 'academic'
  | 'guardian'
  | 'address'
  | 'documents'
  | 'history'
  | 'exams'
  | 'reportcards'
  | 'attendance';

/** Mutable fields bound by the focused section editors. */
interface SectionForm {
  // photo
  PhotoUrl: string;
  // personal
  FirstName: string;
  MiddleName: string;
  LastName: string;
  DateOfBirth: string;
  Gender: string;
  BloodGroup: string;
  Nationality: string;
  Email: string;
  Phone: string;
  // guardian
  GuardianName: string;
  GuardianRelation: string;
  GuardianPhone: string;
  GuardianAltPhone: string;
  GuardianEmail: string;
  // address
  AddressLine1: string;
  AddressLine2: string;
  City: string;
  State: string;
  PostalCode: string;
  Country: string;
}

/**
 * One exam row for the student. Every exam scheduled for the student's class is
 * listed. Published exams also carry the student's result (percentage/grade),
 * which is what powers the Report Cards tab.
 */
interface RecentExamRow {
  examId: number;
  name: string;
  examType: string | null;
  academicYear: string;
  status: string;            // Upcoming | Ongoing | Completed | Published
  published: boolean;
  startDate: string | null;
  endDate: string | null;
  percentage: number | null;
  grade: string | null;
  result: string | null;
}

/**
 * Rich student profile screen. Tabbed layout with an overview dashboard, personal /
 * academic / guardian / address detail, documents, class history and exams. All data
 * comes from the API; actions (edit, status, promote, report card) are wired to the
 * existing services and gated by permissions.
 */
@Component({
  selector: 'app-student-detail',
  imports: [RouterLink, DatePipe, DecimalPipe, FormsModule],
  templateUrl: './student-detail.component.html',
  styleUrl: './student-detail.component.scss'
})
export class StudentDetailComponent {
  private readonly api = inject(StudentService);
  private readonly academic = inject(AcademicService);
  private readonly exams = inject(ExamService);
  private readonly attendance = inject(AttendanceService);
  private readonly route = inject(ActivatedRoute);
  private readonly router = inject(Router);
  private readonly notify = inject(NotificationService);
  protected readonly store = inject(AuthStore);

  protected readonly state = signal<LoadState>('loading');
  protected readonly student = signal<StudentDetail | null>(null);
  protected readonly enrollments = signal<Enrollment[]>([]);
  protected readonly recentExams = signal<RecentExamRow[]>([]);
  protected readonly attendanceRows = signal<AttendanceHistoryRow[]>([]);
  protected readonly activeTab = signal<Tab>('overview');

  // Change-status dialog state.
  protected readonly statusOpen = signal(false);
  protected statusValue = '';
  protected statusReason = '';
  protected readonly statusBusy = signal(false);
  protected readonly statusOptions = ['Active', 'Inactive', 'Graduated', 'Withdrawn'];

  // Promote dialog state.
  protected readonly promoteOpen = signal(false);
  protected readonly classes = signal<SchoolClass[]>([]);
  protected readonly promoteSections = signal<Section[]>([]);
  protected promoteClassId = 0;
  protected promoteSectionId = 0;
  protected promoteNote = '';
  protected readonly promoteBusy = signal(false);

  // Focused section editors (photo / personal / guardian / address).
  protected readonly editSection = signal<'photo' | 'personal' | 'guardian' | 'address' | null>(null);
  protected readonly sectionBusy = signal(false);
  /** Working copy of the fields relevant to the open section. */
  protected form: SectionForm = this.emptyForm();
  protected readonly genders = ['Male', 'Female', 'Other'];
  protected readonly bloodGroups = ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'];

  // Student / guardian users get a read-only profile: no edit, status, deactivate or promote.
  protected readonly selfService = this.store.isStudentOrGuardian();
  protected readonly canUpdate = !this.selfService && this.store.hasPermission('student.update');
  protected readonly canStatus = !this.selfService && this.store.hasPermission('student.status');
  protected readonly canPromote = !this.selfService && this.store.hasPermission('student.promote');
  protected readonly canViewExams = this.store.hasPermission('exam.view');
  protected readonly canViewAttendance = this.store.hasPermission('attendance.view');

  /** Attendance summary counts derived from the loaded history. */
  protected readonly attendanceSummary = computed(() => {
    const rows = this.attendanceRows();
    const by: Record<string, number> = { Present: 0, Absent: 0, Late: 0, Leave: 0 };
    for (const r of rows) by[r.status] = (by[r.status] ?? 0) + 1;
    const total = rows.length;
    const pct = total ? Math.round((by['Present'] / total) * 100) : 0;
    return { total, present: by['Present'], absent: by['Absent'], late: by['Late'], leave: by['Leave'], pct };
  });

  /** Age in whole years from the date of birth, or null if DOB unknown. */
  protected readonly age = computed(() => {
    const dob = this.student()?.date_of_birth;
    if (!dob) return null;
    const birth = new Date(dob);
    if (isNaN(birth.getTime())) return null;
    const now = new Date();
    let years = now.getFullYear() - birth.getFullYear();
    const m = now.getMonth() - birth.getMonth();
    if (m < 0 || (m === 0 && now.getDate() < birth.getDate())) years--;
    return years >= 0 ? years : null;
  });

  constructor() {
    const id = Number(this.route.snapshot.paramMap.get('id'));
    this.load(id);
  }

  private load(id: number): void {
    this.state.set('loading');
    this.api.get(id).subscribe({
      next: (s) => {
        if (!s) {
          this.state.set('error');
          return;
        }
        this.student.set(s);
        this.state.set('success');
        if (this.canViewExams) this.loadExams(s);
        if (this.canViewAttendance) {
          this.attendance.history(s.student_id, 90).subscribe((rows) => this.attendanceRows.set(rows));
        }
      },
      error: () => this.state.set('error')
    });
    this.api.enrollments(id).subscribe((e) => this.enrollments.set(e));
  }

  /**
   * Load every exam scheduled for the student's class (any status), then enrich
   * published exams with the student's result so both the Exams tab and the
   * Report Cards tab have what they need.
   */
  private loadExams(s: StudentDetail): void {
    if (!s.class_id) return;
    this.exams.list({ classId: s.class_id }).subscribe((list) => {
      const rows: RecentExamRow[] = list.map((ex) => ({
        examId: ex.exam_id,
        name: ex.name,
        examType: ex.exam_type,
        academicYear: ex.academic_year_name ?? '—',
        status: ex.status,
        published: ex.is_published,
        startDate: ex.start_date,
        endDate: ex.end_date,
        percentage: null,
        grade: null,
        result: null
      }));
      // Show the list immediately (sorted newest first by start date).
      rows.sort((a, b) => (b.startDate ?? '').localeCompare(a.startDate ?? ''));
      this.recentExams.set([...rows]);

      // Enrich published exams with this student's result (report card data).
      for (const row of rows) {
        if (!row.published) continue;
        this.exams.reportCard(row.examId, s.student_id).subscribe({
          next: (rc) => {
            if (rc) {
              row.percentage = rc.percentage;
              row.grade = rc.grade;
              row.result = rc.result;
              this.recentExams.set([...rows]);
            }
          }
        });
      }
    });
  }

  /** Published exams only — these are the ones with a viewable report card. */
  protected readonly reportCardRows = computed(() =>
    this.recentExams().filter((e) => e.published)
  );

  protected setTab(tab: Tab): void {
    this.activeTab.set(tab);
  }

  // ---- Header actions ----
  protected edit(): void {
    if (!this.canUpdate) return;
    const s = this.student();
    if (s) void this.router.navigate(['/students', s.student_id, 'edit']);
  }

  protected print(): void {
    window.print();
  }

  protected generateReportCard(row?: RecentExamRow): void {
    const s = this.student();
    if (!s) return;
    // Report cards only exist for published exams; fall back to the first published one.
    const examId = row?.examId ?? this.reportCardRows()[0]?.examId;
    if (!examId) {
      this.notify.info('No published exam found for this student yet.');
      return;
    }
    void this.router.navigate(['/exams', examId, 'report-card', s.student_id]);
  }

  // ---- Change status ----
  protected openStatus(): void {
    if (!this.canStatus) return;
    const s = this.student();
    if (!s) return;
    this.statusValue = s.status ?? 'Active';
    this.statusReason = '';
    this.statusOpen.set(true);
  }

  protected closeStatus(): void {
    this.statusOpen.set(false);
  }

  protected confirmStatus(): void {
    const s = this.student();
    if (!s || this.statusBusy()) return;
    if (!this.statusValue) {
      this.notify.info('Choose a status.');
      return;
    }
    if (this.statusValue !== 'Active' && !this.statusReason.trim()) {
      this.notify.info('A reason is required for this status.');
      return;
    }
    this.statusBusy.set(true);
    this.api
      .setStatus(s.student_id, { Status: this.statusValue, Reason: this.statusReason.trim() || null })
      .subscribe({
        next: (res) => {
          this.statusBusy.set(false);
          if (res.isSuccess) {
            this.notify.success(`Status set to ${this.statusValue}.`);
            this.closeStatus();
            this.load(s.student_id);
          } else {
            this.notify.error(res.resultCodeDescription ?? 'Could not update status.');
          }
        },
        error: () => this.statusBusy.set(false)
      });
  }

  /** Deactivate = soft delete (status Inactive). */
  protected deactivate(): void {
    if (!this.canStatus) return;
    const s = this.student();
    if (!s) return;
    if (s.status !== 'Active') {
      this.notify.info('This student is already not Active.');
      return;
    }
    if (!confirm(`Deactivate ${s.first_name} ${s.last_name}? This sets the student Inactive.`)) return;
    this.api.deactivate(s.student_id).subscribe({
      next: (res) => {
        if (res.isSuccess) {
          this.notify.success('Student deactivated.');
          this.load(s.student_id);
        } else {
          this.notify.error(res.resultCodeDescription ?? 'Could not deactivate.');
        }
      }
    });
  }

  // ---- Promote ----
  protected openPromote(): void {
    if (!this.canPromote) return;
    const s = this.student();
    if (!s) return;
    if (s.status !== 'Active') {
      this.notify.error('Only Active students can be promoted.');
      return;
    }
    this.promoteClassId = 0;
    this.promoteSectionId = 0;
    this.promoteNote = '';
    this.promoteSections.set([]);
    if (!this.classes().length) this.academic.listClasses().subscribe((c) => this.classes.set(c));
    this.promoteOpen.set(true);
  }

  protected closePromote(): void {
    this.promoteOpen.set(false);
  }

  protected onPromoteClassChange(): void {
    this.promoteSectionId = 0;
    this.promoteSections.set([]);
    if (this.promoteClassId) {
      this.academic.listSections(this.promoteClassId).subscribe((s) => this.promoteSections.set(s));
    }
  }

  protected confirmPromote(): void {
    const s = this.student();
    if (!s || this.promoteBusy()) return;
    if (!this.promoteClassId) {
      this.notify.info('Choose a target class.');
      return;
    }
    this.promoteBusy.set(true);
    this.api
      .promote({
        StudentIds: [s.student_id],
        ToClassId: this.promoteClassId,
        ToSectionId: this.promoteSectionId || null,
        AcademicYearId: null,
        Note: this.promoteNote || null
      })
      .subscribe({
        next: (res) => {
          this.promoteBusy.set(false);
          if (res.isSuccess && (res.data?.promoted ?? 0) > 0) {
            this.notify.success('Student promoted.');
            this.closePromote();
            this.load(s.student_id);
          } else {
            this.notify.error(res.resultCodeDescription ?? 'Promotion failed.');
          }
        },
        error: () => this.promoteBusy.set(false)
      });
  }

  // ---- Focused section editors ----
  private emptyForm(): SectionForm {
    return {
      PhotoUrl: '',
      FirstName: '', MiddleName: '', LastName: '', DateOfBirth: '',
      Gender: '', BloodGroup: '', Nationality: '', Email: '', Phone: '',
      GuardianName: '', GuardianRelation: '', GuardianPhone: '', GuardianAltPhone: '', GuardianEmail: '',
      AddressLine1: '', AddressLine2: '', City: '', State: '', PostalCode: '', Country: ''
    };
  }

  /** Seed the working form from the current student before opening a section editor. */
  private seedForm(s: StudentDetail): void {
    this.form = {
      PhotoUrl: s.photo_url ?? '',
      FirstName: s.first_name ?? '',
      MiddleName: s.middle_name ?? '',
      LastName: s.last_name ?? '',
      DateOfBirth: s.date_of_birth ? s.date_of_birth.substring(0, 10) : '',
      Gender: s.gender ?? '',
      BloodGroup: s.blood_group ?? '',
      Nationality: s.nationality ?? '',
      Email: s.email ?? '',
      Phone: s.phone ?? '',
      GuardianName: s.guardian_name ?? '',
      GuardianRelation: s.guardian_relation ?? '',
      GuardianPhone: s.guardian_phone ?? '',
      GuardianAltPhone: s.guardian_alt_phone ?? '',
      GuardianEmail: s.guardian_email ?? '',
      AddressLine1: s.address_line1 ?? '',
      AddressLine2: s.address_line2 ?? '',
      City: s.city ?? '',
      State: s.state ?? '',
      PostalCode: s.postal_code ?? '',
      Country: s.country ?? ''
    };
  }

  protected openSection(section: 'photo' | 'personal' | 'guardian' | 'address'): void {
    const s = this.student();
    if (!s) return;
    if (!this.canUpdate) {
      this.notify.error('You do not have permission to edit this student.');
      return;
    }
    this.seedForm(s);
    this.editSection.set(section);
  }

  protected closeSection(): void {
    this.editSection.set(null);
  }

  /** Read an image file as a data URL into the PhotoUrl field (client-side preview/store). */
  protected onPhotoSelected(event: Event): void {
    const input = event.target as HTMLInputElement;
    const file = input.files?.[0];
    if (!file) return;
    if (!file.type.startsWith('image/')) {
      this.notify.error('Please choose an image file.');
      return;
    }
    if (file.size > 2 * 1024 * 1024) {
      this.notify.error('Image is too large. Max 2 MB.');
      return;
    }
    const reader = new FileReader();
    reader.onload = () => { this.form.PhotoUrl = String(reader.result ?? ''); };
    reader.readAsDataURL(file);
  }

  protected clearPhoto(): void {
    this.form.PhotoUrl = '';
  }

  /**
   * Build a complete upsert payload from the current student, overriding only the
   * fields the open section owns. The API's update requires the full record, so we
   * always send everything but only the edited section can change.
   */
  private buildUpsert(s: StudentDetail): StudentUpsert {
    return {
      AdmissionNumber: s.admission_number,
      FirstName: this.form.FirstName.trim() || s.first_name,
      MiddleName: this.form.MiddleName || null,
      LastName: this.form.LastName.trim() || s.last_name,
      Gender: this.form.Gender || null,
      DateOfBirth: this.form.DateOfBirth || null,
      Nationality: this.form.Nationality || null,
      BloodGroup: this.form.BloodGroup || null,
      PhotoUrl: this.form.PhotoUrl || null,
      Email: this.form.Email || null,
      Phone: this.form.Phone || null,
      AddressLine1: this.form.AddressLine1 || null,
      AddressLine2: this.form.AddressLine2 || null,
      City: this.form.City || null,
      State: this.form.State || null,
      PostalCode: this.form.PostalCode || null,
      Country: this.form.Country || null,
      ClassId: s.class_id ?? null,
      SectionId: s.section_id ?? null,
      AcademicYearId: s.academic_year_id ?? null,
      RollNumber: s.roll_number ?? null,
      AdmissionDate: s.admission_date ? s.admission_date.substring(0, 10) : null,
      Status: s.status ?? null,
      GuardianName: this.form.GuardianName || null,
      GuardianRelation: this.form.GuardianRelation || null,
      GuardianPhone: this.form.GuardianPhone || null,
      GuardianAltPhone: this.form.GuardianAltPhone || null,
      GuardianEmail: this.form.GuardianEmail || null
    };
  }

  protected saveSection(): void {
    const s = this.student();
    const section = this.editSection();
    if (!s || !section || this.sectionBusy()) return;

    if (section === 'personal' && (!this.form.FirstName.trim() || !this.form.LastName.trim())) {
      this.notify.info('First name and last name are required.');
      return;
    }

    const body = this.buildUpsert(s);
    this.sectionBusy.set(true);
    this.api.update(s.student_id, body).subscribe({
      next: (res) => {
        this.sectionBusy.set(false);
        if (res.isSuccess) {
          this.notify.success(this.sectionLabel(section) + ' updated.');
          this.closeSection();
          this.load(s.student_id);
        } else {
          this.notify.error(res.resultCodeDescription ?? 'Could not save changes.');
        }
      },
      error: () => {
        this.sectionBusy.set(false);
        this.notify.error('A network or server error occurred.');
      }
    });
  }

  private sectionLabel(section: 'photo' | 'personal' | 'guardian' | 'address'): string {
    switch (section) {
      case 'photo': return 'Photo';
      case 'personal': return 'Personal information';
      case 'guardian': return 'Parent / guardian information';
      case 'address': return 'Address';
    }
  }

  // ---- View helpers ----
  protected initials(s: StudentDetail): string {
    return `${(s.first_name?.[0] ?? '').toUpperCase()}${(s.last_name?.[0] ?? '').toUpperCase()}`;
  }

  protected fullName(s: StudentDetail): string {
    return `${s.first_name} ${s.middle_name ? s.middle_name + ' ' : ''}${s.last_name}`.trim();
  }

  /** Display student code like STU001 (zero-padded, no grouping separators). */
  protected studentCode(id: number): string {
    return `STU${String(id).padStart(3, '0')}`;
  }

  protected statusClass(status: string | null): string {
    switch (status) {
      case 'Active': return 'badge badge--active';
      case 'Graduated': return 'badge badge--grad';
      case 'Withdrawn': return 'badge badge--withdrawn';
      case 'Promoted': return 'badge badge--promoted';
      default: return 'badge badge--inactive';
    }
  }

  protected resultClass(result: string | null): string {
    const r = (result ?? '').toLowerCase();
    if (r.includes('pass')) return 'pill pill--pass';
    if (r.includes('fail')) return 'pill pill--fail';
    return 'pill';
  }

  protected examStatusClass(status: string): string {
    switch (status) {
      case 'Published': return 'badge badge--grad';
      case 'Ongoing': return 'badge badge--active';
      case 'Completed': return 'badge badge--promoted';
      case 'Upcoming': return 'badge badge--inactive';
      default: return 'badge badge--inactive';
    }
  }

  protected attendClass(status: string): string {
    switch (status) {
      case 'Present': return 'pill pill--pass';
      case 'Absent': return 'pill pill--fail';
      case 'Late': return 'badge badge--promoted';
      case 'Leave': return 'badge badge--grad';
      default: return 'pill';
    }
  }
}
