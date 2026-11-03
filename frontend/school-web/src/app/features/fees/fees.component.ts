import { Component, inject, signal } from '@angular/core';
import { DecimalPipe } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { FeeService } from '../../core/services/fee.service';
import { AuthStore } from '../../core/auth/auth.store';
import { NotificationService } from '../../core/services/notification.service';
import { CollectionReport, Defaulter, FeeHead, FeeLedger } from '../../core/models/api.models';

type Tab = 'heads' | 'collect' | 'defaulters' | 'reports';

@Component({
  selector: 'app-fees',
  imports: [FormsModule, DecimalPipe],
  templateUrl: './fees.component.html',
  styleUrl: './fees.component.scss'
})
export class FeesComponent {
  private readonly api = inject(FeeService);
  private readonly notify = inject(NotificationService);
  protected readonly store = inject(AuthStore);

  protected readonly tab = signal<Tab>('collect');
  protected readonly heads = signal<FeeHead[]>([]);
  protected readonly ledger = signal<FeeLedger | null>(null);
  protected readonly defaulters = signal<Defaulter[]>([]);
  protected readonly report = signal<CollectionReport | null>(null);
  protected readonly busy = signal(false);

  protected readonly canManage = this.store.hasPermission('fee.manage');
  protected readonly canCollect = this.store.hasPermission('fee.collect');

  // forms (ngModel)
  protected headName = '';
  protected headCode = '';
  protected ledgerStudentId: number | null = null;
  protected assignHeadId = 0;
  protected assignAmount: number | null = null;
  protected payAmount: number | null = null;
  protected payMode = 'Cash';

  constructor() {
    this.api.listHeads().subscribe((h) => this.heads.set(h));
  }

  protected setTab(t: Tab): void {
    this.tab.set(t);
    if (t === 'defaulters') this.loadDefaulters();
    if (t === 'reports') this.loadReport();
  }

  protected addHead(): void {
    if (!this.headName || !this.headCode) { this.notify.info('Name and code required.'); return; }
    this.busy.set(true);
    this.api.saveHead({ Name: this.headName, Code: this.headCode, IsActive: true }).subscribe({
      next: (r) => { this.busy.set(false); if (r.isSuccess) { this.notify.success('Fee head saved.'); this.headName = ''; this.headCode = ''; this.api.listHeads().subscribe((h) => this.heads.set(h)); } else this.notify.error(r.resultCodeDescription ?? 'Failed.'); },
      error: () => this.busy.set(false)
    });
  }

  protected loadLedger(): void {
    if (!this.ledgerStudentId) { this.notify.info('Enter a student id.'); return; }
    this.api.ledger(this.ledgerStudentId).subscribe((l) => this.ledger.set(l));
  }

  protected assign(): void {
    if (!this.ledgerStudentId || !this.assignHeadId || !this.assignAmount) { this.notify.info('Student, fee head and amount required.'); return; }
    this.busy.set(true);
    this.api.assign({ StudentId: this.ledgerStudentId, FeeHeadId: this.assignHeadId, Amount: this.assignAmount, Discount: 0 }).subscribe({
      next: (r) => { this.busy.set(false); if (r.isSuccess) { this.notify.success('Fee assigned.'); this.assignAmount = null; this.loadLedger(); } else this.notify.error(r.resultCodeDescription ?? 'Failed.'); },
      error: () => this.busy.set(false)
    });
  }

  protected pay(): void {
    if (!this.ledgerStudentId || !this.payAmount) { this.notify.info('Student and amount required.'); return; }
    this.busy.set(true);
    this.api.pay({ StudentId: this.ledgerStudentId, Amount: this.payAmount, Mode: this.payMode }).subscribe({
      next: (r) => {
        this.busy.set(false);
        if (r.isSuccess) {
          const data = r.data as { receipt_number?: string } | null;
          this.notify.success(`Payment recorded. Receipt ${data?.receipt_number ?? ''}`);
          this.payAmount = null; this.loadLedger();
        } else this.notify.error(r.resultCodeDescription ?? 'Failed.');
      },
      error: () => this.busy.set(false)
    });
  }

  protected loadDefaulters(): void { this.api.defaulters().subscribe((d) => this.defaulters.set(d)); }
  protected loadReport(): void { this.api.collection().subscribe((r) => this.report.set(r)); }

  protected modes(r: CollectionReport | null): { mode: string; amt: number }[] {
    if (!r?.by_mode) return [];
    return Object.entries(r.by_mode).map(([mode, amt]) => ({ mode, amt: amt as number }));
  }
}
