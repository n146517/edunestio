import { Component, computed, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { DatePipe } from '@angular/common';
import { AttendanceService } from '../../core/services/attendance.service';
import { AcademicService } from '../../core/services/academic.service';
import { SettingsService } from '../../core/services/settings.service';
import { AuthStore } from '../../core/auth/auth.store';
import { NotificationService } from '../../core/services/notification.service';
import { AttendanceSheetRow, AttendanceStatus, SchoolClass, Section, Subject } from '../../core/models/api.models';

type LoadState = 'idle' | 'loading' | 'success' | 'error';

@Component({
  selector: 'app-attendance',
  imports: [FormsModule, DatePipe],
  templateUrl: './attendance.component.html',
  styleUrl: './attendance.component.scss'
})
export class AttendanceComponent {
  private readonly api = inject(AttendanceService);
  private readonly academic = inject(AcademicService);
  private readonly settings = inject(SettingsService);
  private readonly notify = inject(NotificationService);
  protected readonly store = inject(AuthStore);

  protected readonly classes = signal<SchoolClass[]>([]);
  protected readonly sections = signal<Section[]>([]);
  protected readonly subjects = signal<Subject[]>([]);
  protected readonly rows = signal<AttendanceSheetRow[]>([]);
  protected readonly state = signal<LoadState>('idle');
  protected readonly saving = signal(false);

  /** 'Daily' = one attendance/day; 'Subject' = per-subject (period-wise). */
  protected readonly mode = signal<'Daily' | 'Subject'>('Daily');

  protected classId = 0;
  protected sectionId = 0;
  protected subjectId = 0;
  protected date = new Date().toISOString().slice(0, 10);
  protected readonly statuses: AttendanceStatus[] = ['Present', 'Absent', 'Late', 'Leave'];

  protected readonly canMark = this.store.hasPermission('attendance.mark');

  // Summary derived from the current sheet.
  protected readonly summary = computed(() => {
    const rows = this.rows();
    const by: Record<string, number> = { Present: 0, Absent: 0, Late: 0, Leave: 0 };
    for (const r of rows) by[r.status] = (by[r.status] ?? 0) + 1;
    const total = rows.length;
    const pct = total ? Math.round((by['Present'] / total) * 100) : 0;
    return { total, present: by['Present'], absent: by['Absent'], late: by['Late'], leave: by['Leave'], pct };
  });

  protected readonly isSubjectMode = computed(() => this.mode() === 'Subject');

  /** True when at least one row already has a saved attendance record for this date. */
  protected readonly alreadyMarked = computed(() => this.rows().some((r) => r.marked));
  /** How many of the loaded students already have a record saved. */
  protected readonly markedCount = computed(() => this.rows().filter((r) => r.marked).length);

  constructor() {
    this.academic.listClasses().subscribe((c) => this.classes.set(c));
    // Discover how this school takes attendance, and load subjects if subject-wise.
    this.settings.get().subscribe((s) => {
      if (s?.attendance_mode) this.mode.set(s.attendance_mode);
      if (this.isSubjectMode()) {
        this.academic.listSubjects().subscribe((subs) => this.subjects.set(subs.filter((x) => x.is_active)));
      }
    });
  }

  protected onClassChange(): void {
    this.sectionId = 0;
    this.sections.set([]);
    this.rows.set([]);
    this.state.set('idle');
    if (this.classId) this.academic.listSections(this.classId).subscribe((s) => this.sections.set(s));
  }

  protected canLoad(): boolean {
    if (!this.classId) return false;
    if (this.isSubjectMode() && !this.subjectId) return false;
    return true;
  }

  protected loadSheet(): void {
    if (!this.classId) { this.notify.info('Select a class first.'); return; }
    if (this.isSubjectMode() && !this.subjectId) { this.notify.info('Select a subject.'); return; }
    this.state.set('loading');
    this.api.sheet(this.classId, this.date, this.sectionId || undefined,
      this.isSubjectMode() ? (this.subjectId || undefined) : undefined).subscribe({
      next: (s) => { this.rows.set(s?.items ?? []); this.state.set('success'); },
      error: () => this.state.set('error')
    });
  }

  protected setStatus(row: AttendanceSheetRow, status: AttendanceStatus): void {
    if (row.on_leave) return; // locked: approved leave stays 'Leave'
    this.rows.update((list) => list.map((r) => (r.student_id === row.student_id ? { ...r, status } : r)));
  }

  protected markAll(status: AttendanceStatus): void {
    // Students on approved leave are never changed by a bulk action.
    this.rows.update((list) => list.map((r) => (r.on_leave ? r : { ...r, status })));
  }

  protected save(): void {
    if (!this.rows().length || this.saving()) return;
    this.saving.set(true);
    this.api.mark({
      ClassId: this.classId,
      SectionId: this.sectionId || null,
      SubjectId: this.isSubjectMode() ? (this.subjectId || null) : null,
      AttendDate: this.date,
      Entries: this.rows().map((r) => ({ StudentId: r.student_id, Status: r.status, Remark: r.remark }))
    }).subscribe({
      next: (r) => {
        this.saving.set(false);
        if (r.isSuccess) { this.notify.success('Attendance saved.'); this.loadSheet(); }
        else this.notify.error(r.resultCodeDescription ?? 'Save failed.');
      },
      error: () => this.saving.set(false)
    });
  }

  protected statusClass(status: string): string {
    switch (status) {
      case 'Present': return 'st st--present';
      case 'Absent': return 'st st--absent';
      case 'Late': return 'st st--late';
      case 'Leave': return 'st st--leave';
      default: return 'st';
    }
  }
}
