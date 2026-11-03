import { Component, effect, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Router, RouterLink } from '@angular/router';
import { DatePipe } from '@angular/common';
import { StudentService } from '../../core/services/student.service';
import { AcademicService } from '../../core/services/academic.service';
import { AuthStore } from '../../core/auth/auth.store';
import { AcademicYearStore } from '../../core/state/academic-year.store';
import { NotificationService } from '../../core/services/notification.service';
import {
  AcademicYear,
  SchoolClass,
  Section,
  Student,
  StudentImportPreview,
  StudentSummary
} from '../../core/models/api.models';

type LoadState = 'loading' | 'success' | 'error';

/** Student records: summary cards, search, filters, paginated table, status actions. */
@Component({
  selector: 'app-students',
  imports: [FormsModule, RouterLink, DatePipe],
  templateUrl: './students.component.html',
  styleUrl: './students.component.scss'
})
export class StudentsComponent {
  private readonly api = inject(StudentService);
  private readonly academic = inject(AcademicService);
  private readonly notify = inject(NotificationService);
  private readonly router = inject(Router);
  protected readonly store = inject(AuthStore);
  private readonly yearStore = inject(AcademicYearStore);

  protected readonly state = signal<LoadState>('loading');
  protected readonly items = signal<Student[]>([]);
  protected readonly total = signal(0);
  protected readonly summary = signal<StudentSummary | null>(null);

  // Master data for filters (loaded from the backend, never hard-coded).
  protected readonly classes = signal<SchoolClass[]>([]);
  protected readonly sections = signal<Section[]>([]);
  protected readonly years = signal<AcademicYear[]>([]);

  // Filter state.
  protected search = '';
  protected classId = 0;
  protected sectionId = 0;
  protected yearId = 0;
  protected status = '';
  protected readonly page = signal(1);
  protected pageSize = 20;

  // Bulk selection + promote dialog.
  protected readonly selected = signal<Set<number>>(new Set<number>());
  protected readonly promoteOpen = signal(false);
  protected promoteClassId = 0;
  protected promoteSectionId = 0;
  protected promoteYearId = 0;
  protected promoteNote = '';
  protected readonly promoteSections = signal<Section[]>([]);
  protected readonly bulkBusy = signal(false);

  protected readonly canCreate = this.store.hasPermission('student.create');
  protected readonly canUpdate = this.store.hasPermission('student.update');
  protected readonly canStatus = this.store.hasPermission('student.status');
  protected readonly canDelete = this.store.hasPermission('student.delete');
  protected readonly canPromote = this.store.hasPermission('student.promote');

  protected readonly statuses = ['Active', 'Inactive', 'Graduated', 'Withdrawn'];

  // Bulk Excel import.
  protected readonly importOpen = signal(false);
  protected readonly importPreview = signal<StudentImportPreview | null>(null);
  protected importFile: File | null = null;
  protected readonly importing = signal(false);
  protected readonly committing = signal(false);

  constructor() {
    this.academic.listClasses().subscribe((c) => this.classes.set(c));
    this.academic.listYears().subscribe((y) => this.years.set(y));
    // Follow the global academic year: default this screen's filter to it and
    // reload whenever the header switcher changes. Users can still override to a
    // different year or "All years" via the on-page filter.
    this.yearStore.load();
    effect(() => {
      const gy = this.yearStore.selectedId();
      if (this.yearId !== gy) {
        this.yearId = gy;
        this.page.set(1);
        this.load();
      }
    });
    this.loadSummary();
    this.load();
  }

  protected totalPages(): number {
    return Math.max(1, Math.ceil(this.total() / this.pageSize));
  }

  protected loadSummary(): void {
    this.api.summary().subscribe((s) => this.summary.set(s));
  }

  protected load(): void {
    this.state.set('loading');
    this.api
      .list({
        search: this.search || undefined,
        classId: this.classId || undefined,
        sectionId: this.sectionId || undefined,
        academicYearId: this.yearId || undefined,
        status: this.status || undefined,
        page: this.page(),
        pageSize: this.pageSize
      })
      .subscribe({
        next: (p) => {
          this.items.set(p?.items ?? []);
          this.total.set(p?.total_count ?? 0);
          this.state.set('success');
        },
        error: () => this.state.set('error')
      });
  }

  protected onClassChange(): void {
    this.sectionId = 0;
    this.sections.set([]);
    if (this.classId) {
      this.academic.listSections(this.classId).subscribe((s) => this.sections.set(s));
    }
    this.applyFilters();
  }

  protected applyFilters(): void {
    this.page.set(1);
    this.load();
  }

  protected applySearch(): void {
    this.page.set(1);
    this.load();
  }

  protected resetFilters(): void {
    this.search = '';
    this.classId = 0;
    this.sectionId = 0;
    this.yearId = 0;
    this.status = '';
    this.sections.set([]);
    this.page.set(1);
    this.load();
  }

  protected changePage(delta: number): void {
    const next = this.page() + delta;
    if (next >= 1 && next <= this.totalPages()) {
      this.page.set(next);
      this.load();
    }
  }

  protected onPageSizeChange(): void {
    this.page.set(1);
    this.load();
  }

  protected admit(): void {
    void this.router.navigate(['/students/new']);
  }

  protected view(s: Student): void {
    void this.router.navigate(['/students', s.student_id]);
  }

  protected edit(s: Student): void {
    void this.router.navigate(['/students', s.student_id, 'edit']);
  }


  // ---- Bulk selection ----
  protected isSelected(id: number): boolean {
    return this.selected().has(id);
  }

  protected toggleSelect(s: Student): void {
    const next = new Set(this.selected());
    if (next.has(s.student_id)) { next.delete(s.student_id); } else { next.add(s.student_id); }
    this.selected.set(next);
  }

  protected allOnPageSelected(): boolean {
    const rows = this.items();
    return rows.length > 0 && rows.every((r) => this.selected().has(r.student_id));
  }

  protected toggleSelectAll(): void {
    const next = new Set(this.selected());
    if (this.allOnPageSelected()) {
      this.items().forEach((r) => next.delete(r.student_id));
    } else {
      this.items().forEach((r) => next.add(r.student_id));
    }
    this.selected.set(next);
  }

  /** Whether any selected row is currently Active / not-Active (drives which bulk buttons show). */
  protected anySelectedActive(): boolean {
    return this.items().some((r) => this.selected().has(r.student_id) && r.status === 'Active');
  }
  protected anySelectedInactive(): boolean {
    return this.items().some((r) => this.selected().has(r.student_id) && r.status !== 'Active');
  }

  protected clearSelection(): void {
    this.selected.set(new Set<number>());
  }

  protected selectedIds(): number[] {
    return Array.from(this.selected());
  }

  private afterBulk(): void {
    this.clearSelection();
    this.loadSummary();
    this.load();
  }

  // ---- Promote ----
  protected openPromote(): void {
    if (!this.selectedIds().length) { this.notify.info('Select at least one student.'); return; }
    if (this.selectedActiveCount() === 0) {
      this.notify.error('None of the selected students are Active. Only Active students can be promoted.');
      return;
    }
    this.promoteClassId = 0;
    this.promoteSectionId = 0;
    this.promoteYearId = 0;
    this.promoteNote = '';
    this.promoteSections.set([]);
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

  /** Count selected rows that are currently Active (the only ones eligible to promote/graduate). */
  private selectedActiveCount(): number {
    return this.items().filter((r) => this.selected().has(r.student_id) && r.status === 'Active').length;
  }

  /** Show an accurate message based on how many of the requested students were actually affected. */
  private reportBulkResult(verb: string, done: number, requested: number): void {
    const skipped = requested - done;
    if (done === 0) {
      this.notify.error(`No students were ${verb}. Only Active students can be ${verb} — ${skipped} skipped.`);
    } else if (skipped > 0) {
      this.notify.info(`${verb[0].toUpperCase() + verb.slice(1)} ${done} student(s); ${skipped} skipped (not Active).`);
    } else {
      this.notify.success(`${verb[0].toUpperCase() + verb.slice(1)} ${done} student(s).`);
    }
  }

  protected confirmPromote(): void {
    if (!this.promoteClassId) { this.notify.info('Choose a target class.'); return; }
    if (this.bulkBusy()) return;
    const requested = this.selectedIds().length;
    this.bulkBusy.set(true);
    this.api.promote({
      StudentIds: this.selectedIds(),
      ToClassId: this.promoteClassId,
      ToSectionId: this.promoteSectionId || null,
      AcademicYearId: this.promoteYearId || null,
      Note: this.promoteNote || null
    }).subscribe({
      next: (res) => {
        this.bulkBusy.set(false);
        if (res.isSuccess) {
          this.reportBulkResult('promoted', res.data?.promoted ?? 0, requested);
          this.closePromote();
          this.afterBulk();
        } else {
          this.notify.error(res.resultCodeDescription ?? 'Promotion failed.');
        }
      },
      error: () => this.bulkBusy.set(false)
    });
  }

  protected graduateSelected(): void {
    const ids = this.selectedIds();
    if (!ids.length) { this.notify.info('Select at least one student.'); return; }
    if (!confirm(`Graduate ${ids.length} student(s)? This sets them Graduated (terminal). Only Active students are affected.`)) return;
    this.api.graduate({ StudentIds: ids, Note: 'Graduated' }).subscribe({
      next: (res) => {
        if (res.isSuccess) { this.reportBulkResult('graduated', res.data?.graduated ?? 0, ids.length); this.afterBulk(); }
        else { this.notify.error(res.resultCodeDescription ?? 'Graduation failed.'); }
      }
    });
  }

  protected withdrawSelected(): void {
    const ids = this.selectedIds();
    if (!ids.length) { this.notify.info('Select at least one student.'); return; }
    const reason = prompt(`Withdraw ${ids.length} student(s). Enter a reason:`);
    if (reason === null) return;
    if (!reason.trim()) { this.notify.info('A reason is required to withdraw.'); return; }
    this.api.withdraw({ StudentIds: ids, Reason: reason.trim() }).subscribe({
      next: (res) => {
        if (res.isSuccess) { this.notify.success(`Withdrew ${res.data?.withdrawn ?? 0} student(s).`); this.afterBulk(); }
        else { this.notify.error(res.resultCodeDescription ?? 'Withdrawal failed.'); }
      }
    });
  }

  /** Bulk set Inactive (reason asked). Applies only to currently-Active selected students. */
  protected inactivateSelected(): void {
    const targets = this.items().filter((r) => this.selected().has(r.student_id) && r.status === 'Active');
    if (!targets.length) { this.notify.info('Select at least one Active student.'); return; }
    const reason = prompt(`Set ${targets.length} student(s) Inactive. Enter a reason:`);
    if (reason === null) return;
    if (!reason.trim()) { this.notify.info('A reason is required.'); return; }
    this.bulkSetStatus(targets.map((t) => t.student_id), 'Inactive', reason.trim());
  }

  /** Bulk set Active (reactivate). Applies only to currently non-Active selected students. */
  protected activateSelected(): void {
    const targets = this.items().filter((r) => this.selected().has(r.student_id) && r.status !== 'Active');
    if (!targets.length) { this.notify.info('Select at least one non-Active student.'); return; }
    this.bulkSetStatus(targets.map((t) => t.student_id), 'Active', 'Reactivated');
  }

  private bulkSetStatus(ids: number[], status: string, reason: string): void {
    if (this.bulkBusy()) return;
    this.bulkBusy.set(true);
    let done = 0;
    let ok = 0;
    ids.forEach((id) => {
      this.api.setStatus(id, { Status: status, Reason: reason }).subscribe({
        next: (res) => {
          done++;
          if (res.isSuccess) ok++;
          if (done === ids.length) {
            this.bulkBusy.set(false);
            this.notify.success(`Set ${ok} student(s) to ${status}.`);
            this.afterBulk();
          }
        },
        error: () => {
          done++;
          if (done === ids.length) { this.bulkBusy.set(false); this.afterBulk(); }
        }
      });
    });
  }

  // ---- Bulk Excel import ----
  protected downloadTemplate(): void {
    this.api.downloadTemplate().subscribe({
      next: (blob) => {
        const url = URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url;
        a.download = 'student_import_template.xlsx';
        a.click();
        URL.revokeObjectURL(url);
      },
      error: () => this.notify.error('Could not download the template.')
    });
  }

  protected openImport(): void {
    this.importFile = null;
    this.importPreview.set(null);
    this.importOpen.set(true);
  }

  protected closeImport(): void {
    this.importOpen.set(false);
  }

  protected onImportFile(ev: Event): void {
    const input = ev.target as HTMLInputElement;
    this.importFile = input.files?.[0] ?? null;
    this.importPreview.set(null);
  }

  protected runImportPreview(): void {
    if (!this.importFile) { this.notify.info('Choose the filled .xlsx file.'); return; }
    this.importing.set(true);
    this.api.importPreview(this.importFile).subscribe({
      next: (p) => {
        this.importing.set(false);
        this.importPreview.set(p);
        if (!p) this.notify.error('Could not read the file.');
        else if (!p.Rows.length) this.notify.info('No student rows found in the file.');
      },
      error: () => { this.importing.set(false); this.notify.error('Import failed. Use the provided template.'); }
    });
  }

  protected commitImport(): void {
    const p = this.importPreview();
    if (!p) return;
    const valid = p.Rows.filter((r) => r.Status === 'Valid');
    if (!valid.length) { this.notify.info('No valid rows to import. Fix the errors and re-upload.'); return; }
    if (this.committing()) return;
    this.committing.set(true);
    this.api.commitImport(valid).subscribe({
      next: (res) => {
        this.committing.set(false);
        if (res) {
          if (res.created > 0) this.notify.success(`Imported ${res.created} student(s).`);
          if (res.failed > 0) this.notify.error(`${res.failed} row(s) failed. ${res.errors.slice(0, 3).join(' | ')}`);
          this.closeImport();
          this.loadSummary();
          this.load();
        } else {
          this.notify.error('Import could not be completed.');
        }
      },
      error: () => { this.committing.set(false); this.notify.error('Import failed.'); }
    });
  }

  protected initials(s: Student): string {
    return `${(s.first_name?.[0] ?? '').toUpperCase()}${(s.last_name?.[0] ?? '').toUpperCase()}`;
  }

  protected statusClass(status: string | null): string {
    switch (status) {
      case 'Active': return 'badge badge--active';
      case 'Graduated': return 'badge badge--grad';
      case 'Withdrawn': return 'badge badge--withdrawn';
      default: return 'badge badge--inactive';
    }
  }
}
