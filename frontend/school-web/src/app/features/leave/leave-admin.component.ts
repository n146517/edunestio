import { Component, inject, signal } from '@angular/core';
import { DatePipe } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { LeaveService } from '../../core/services/leave.service';
import { NotificationService } from '../../core/services/notification.service';
import { LeaveRequest } from '../../core/models/api.models';

type LoadState = 'loading' | 'success' | 'error';

/** Staff screen: review, approve or reject student leave requests. */
@Component({
  selector: 'app-leave-admin',
  imports: [DatePipe, FormsModule],
  templateUrl: './leave-admin.component.html',
  styleUrl: './leave.component.scss'
})
export class LeaveAdminComponent {
  private readonly api = inject(LeaveService);
  private readonly notify = inject(NotificationService);

  protected readonly state = signal<LoadState>('loading');
  protected readonly items = signal<LeaveRequest[]>([]);
  protected readonly busyId = signal<number | null>(null);

  protected status = 'Pending';
  protected search = '';
  protected readonly statuses = ['Pending', 'Approved', 'Rejected', 'Cancelled'];

  constructor() { this.load(); }

  protected load(): void {
    this.state.set('loading');
    this.api.list({ status: this.status || undefined, search: this.search || undefined }).subscribe({
      next: (list) => { this.items.set(list); this.state.set('success'); },
      error: () => this.state.set('error')
    });
  }

  protected decide(l: LeaveRequest, decision: 'Approved' | 'Rejected'): void {
    if (this.busyId()) return;
    let note: string | null = null;
    if (decision === 'Rejected') {
      note = prompt('Reason for rejection (optional):');
      if (note === null) return; // cancelled the prompt
    } else if (!confirm(`Approve leave for ${l.first_name} ${l.last_name}? This will mark those days as Leave in attendance.`)) {
      return;
    }
    this.busyId.set(l.leave_id);
    this.api.decide(l.leave_id, { Decision: decision, Note: note || null }).subscribe({
      next: (res) => {
        this.busyId.set(null);
        if (res.isSuccess) { this.notify.success(`Leave ${decision.toLowerCase()}.`); this.load(); }
        else { this.notify.error(res.resultCodeDescription ?? 'Could not update.'); }
      },
      error: () => this.busyId.set(null)
    });
  }

  protected statusClass(s: string): string {
    switch (s) {
      case 'Approved': return 'badge badge--approved';
      case 'Rejected': return 'badge badge--rejected';
      case 'Cancelled': return 'badge badge--cancelled';
      default: return 'badge badge--pending';
    }
  }
}
