import { Component, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Router, RouterLink } from '@angular/router';
import { LeaveService } from '../../core/services/leave.service';
import { NotificationService } from '../../core/services/notification.service';

/** Student self-service: apply for a leave. */
@Component({
  selector: 'app-leave-apply',
  imports: [FormsModule, RouterLink],
  templateUrl: './leave-apply.component.html',
  styleUrl: './leave.component.scss'
})
export class LeaveApplyComponent {
  private readonly api = inject(LeaveService);
  private readonly notify = inject(NotificationService);
  private readonly router = inject(Router);

  protected fromDate = '';
  protected toDate = '';
  protected leaveType = 'Sick';
  protected reason = '';
  protected readonly busy = signal(false);
  protected readonly types = ['Sick', 'Casual', 'Other'];

  protected submit(): void {
    if (this.busy()) return;
    if (!this.fromDate || !this.toDate) { this.notify.info('Choose the leave dates.'); return; }
    if (this.toDate < this.fromDate) { this.notify.error('To date cannot be before From date.'); return; }
    if (!this.reason.trim()) { this.notify.info('Please enter a reason.'); return; }

    this.busy.set(true);
    this.api.apply({
      FromDate: this.fromDate,
      ToDate: this.toDate,
      LeaveType: this.leaveType,
      Reason: this.reason.trim()
    }).subscribe({
      next: (res) => {
        this.busy.set(false);
        if (res.isSuccess) {
          this.notify.success('Leave request submitted.');
          void this.router.navigate(['/leave/mine']);
        } else {
          this.notify.error(res.resultCodeDescription ?? 'Could not submit leave.');
        }
      },
      error: () => { this.busy.set(false); this.notify.error('A network or server error occurred.'); }
    });
  }
}
