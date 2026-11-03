import { Component, inject, signal } from '@angular/core';
import { DatePipe } from '@angular/common';
import { RouterLink } from '@angular/router';
import { LeaveService } from '../../core/services/leave.service';
import { NotificationService } from '../../core/services/notification.service';
import { LeaveRequest } from '../../core/models/api.models';

type LoadState = 'loading' | 'success' | 'error';

/** Student self-service: list of my leave requests, with cancel for pending ones. */
@Component({
  selector: 'app-my-leaves',
  imports: [DatePipe, RouterLink],
  templateUrl: './my-leaves.component.html',
  styleUrl: './leave.component.scss'
})
export class MyLeavesComponent {
  private readonly api = inject(LeaveService);
  private readonly notify = inject(NotificationService);

  protected readonly state = signal<LoadState>('loading');
  protected readonly items = signal<LeaveRequest[]>([]);

  constructor() { this.load(); }

  protected load(): void {
    this.state.set('loading');
    this.api.mine().subscribe({
      next: (list) => { this.items.set(list); this.state.set('success'); },
      error: () => this.state.set('error')
    });
  }

  protected cancel(l: LeaveRequest): void {
    if (l.status !== 'Pending') return;
    if (!confirm('Cancel this leave request?')) return;
    this.api.cancel(l.leave_id).subscribe({
      next: (res) => {
        if (res.isSuccess) { this.notify.success('Leave cancelled.'); this.load(); }
        else { this.notify.error(res.resultCodeDescription ?? 'Could not cancel.'); }
      }
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
