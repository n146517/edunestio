import { Component, inject, signal } from '@angular/core';
import { RouterLink } from '@angular/router';
import { ApiService } from '../../core/services/api.service';
import { AuthStore } from '../../core/auth/auth.store';
import { StatusData } from '../../core/models/api.models';

type LoadState = 'loading' | 'success' | 'error';

interface ModuleCard {
  label: string;
  desc: string;
  icon: string;
  route: string[];
  planned?: boolean;
}

@Component({
  selector: 'app-dashboard',
  imports: [RouterLink],
  templateUrl: './dashboard.component.html',
  styleUrl: './dashboard.component.scss'
})
export class DashboardComponent {
  private readonly api = inject(ApiService);
  protected readonly store = inject(AuthStore);

  protected readonly state = signal<LoadState>('loading');
  protected readonly status = signal<StatusData | null>(null);

  /** Card-based module discovery (inspired by the brief's screenshots). */
  protected readonly modules: ModuleCard[] = [
    { label: 'Students', desc: 'Admissions, profiles, class enrolment and records.', icon: 'icons/students.svg', route: ['/students'] },
    { label: 'Academic Setup', desc: 'Years, classes, sections and subjects.', icon: 'icons/academic.svg', route: ['/academic-setup'] },
    { label: 'Admissions', desc: 'Enquiries, follow-ups and convert to students.', icon: 'icons/admissions.svg', route: ['/admissions'] },
    { label: 'Attendance', desc: 'Daily and class-wise attendance marking.', icon: 'icons/attendance.svg', route: ['/attendance'] },
    { label: 'Fees & Finance', desc: 'Fee structures, invoices, receipts and dues.', icon: 'icons/fees.svg', route: ['/fees'] },
    { label: 'Exams & Report Cards', desc: 'Exam setup, marks entry, grading and results.', icon: 'icons/exams.svg', route: ['/exams'] }
  ];

  constructor() {
    this.loadStatus();
  }

  protected loadStatus(): void {
    this.state.set('loading');
    this.api.getStatus().subscribe({
      next: (s) => {
        this.status.set(s);
        this.state.set('success');
      },
      error: () => this.state.set('error')
    });
  }
}
