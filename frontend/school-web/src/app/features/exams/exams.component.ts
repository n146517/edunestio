import { Component, computed, effect, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Router } from '@angular/router';
import { DatePipe } from '@angular/common';
import { ExamService } from '../../core/services/exam.service';
import { AcademicService } from '../../core/services/academic.service';
import { AuthStore } from '../../core/auth/auth.store';
import { AcademicYearStore } from '../../core/state/academic-year.store';
import { NotificationService } from '../../core/services/notification.service';
import { AcademicYear, Exam, SchoolClass } from '../../core/models/api.models';
import { ExamTabsComponent } from './exam-tabs.component';

type LoadState = 'loading' | 'success' | 'error';
type Tab = 'All' | 'Upcoming' | 'Ongoing' | 'Completed' | 'Published';

/** Examination list (screen 1): status tabs, filters, search, exam table. */
@Component({
  selector: 'app-exams',
  imports: [FormsModule, DatePipe, ExamTabsComponent],
  templateUrl: './exams.component.html',
  styleUrl: './exams.component.scss'
})
export class ExamsComponent {
  private readonly api = inject(ExamService);
  private readonly academic = inject(AcademicService);
  private readonly notify = inject(NotificationService);
  private readonly router = inject(Router);
  protected readonly store = inject(AuthStore);
  private readonly yearStore = inject(AcademicYearStore);

  protected readonly state = signal<LoadState>('loading');
  protected readonly exams = signal<Exam[]>([]);
  protected readonly classes = signal<SchoolClass[]>([]);
  protected readonly years = signal<AcademicYear[]>([]);

  protected readonly tab = signal<Tab>('All');
  protected readonly tabs: Tab[] = ['All', 'Upcoming', 'Ongoing', 'Completed', 'Published'];

  protected search = '';
  protected classId = 0;
  protected yearId = 0;
  protected statusFilter = '';

  protected readonly canManage = this.store.hasPermission('exam.manage');

  /** Exams filtered by the active status tab (server already applied other filters). */
  protected readonly visible = computed(() => {
    const t = this.tab();
    const rows = this.exams();
    return t === 'All' ? rows : rows.filter((e) => e.status === t);
  });

  protected count(t: Tab): number {
    const rows = this.exams();
    return t === 'All' ? rows.length : rows.filter((e) => e.status === t).length;
  }

  constructor() {
    this.academic.listClasses().subscribe((c) => this.classes.set(c));
    this.academic.listYears().subscribe((y) => this.years.set(y));
    // Follow the global academic year selected in the header.
    this.yearStore.load();
    effect(() => {
      const gy = this.yearStore.selectedId();
      if (this.yearId !== gy) { this.yearId = gy; this.load(); }
    });
    this.load();
  }

  protected load(): void {
    this.state.set('loading');
    this.api
      .list({
        search: this.search || undefined,
        classId: this.classId || undefined,
        academicYearId: this.yearId || undefined,
        status: this.statusFilter || undefined
      })
      .subscribe({
        next: (e) => { this.exams.set(e); this.state.set('success'); },
        error: () => this.state.set('error')
      });
  }

  protected setTab(t: Tab): void {
    this.tab.set(t);
  }

  protected resetFilters(): void {
    this.search = '';
    this.classId = 0;
    this.yearId = 0;
    this.statusFilter = '';
    this.tab.set('All');
    this.load();
  }

  protected createExam(): void {
    void this.router.navigate(['/exams/new']);
  }

  protected view(e: Exam): void {
    void this.router.navigate(['/exams', e.exam_id]);
  }

  protected edit(e: Exam): void {
    void this.router.navigate(['/exams', e.exam_id, 'edit']);
  }

  protected classLabel(e: Exam): string {
    if (!e.classes?.length) return '—';
    if (e.classes.length <= 2) return e.classes.map((c) => c.name).join(', ');
    return `${e.classes[0].name} +${e.classes.length - 1} more`;
  }

  protected statusClass(status: string): string {
    switch (status) {
      case 'Published': return 'badge badge--pub';
      case 'Completed': return 'badge badge--done';
      case 'Ongoing': return 'badge badge--ongoing';
      default: return 'badge badge--upcoming';
    }
  }
}
