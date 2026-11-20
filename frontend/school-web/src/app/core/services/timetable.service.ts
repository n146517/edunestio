import { HttpClient, HttpParams } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable, map } from 'rxjs';
import { environment } from '../../../environments/environment';
import {
  ApiResponse, ItemsData, MyTimetable, PeriodScheduleItem, PeriodScheduleSaveResult,
  Teacher, TeacherSchedule, TimetableSlot, TimetableSlotUpsert
} from '../models/api.models';

/** Typed client for the Timetable module. */
@Injectable({ providedIn: 'root' })
export class TimetableService {
  private readonly http = inject(HttpClient);
  private readonly base = `${environment.apiBaseUrl}/timetable`;

  /** Teachers of the school (for the slot teacher dropdown). */
  teachers(): Observable<Teacher[]> {
    return this.http
      .get<ApiResponse<ItemsData<Teacher>>>(`${this.base}/teachers`)
      .pipe(map((r) => r.data?.items ?? []));
  }

  /** Slots for a class (optionally a section). */
  list(classId: number, sectionId?: number): Observable<TimetableSlot[]> {
    let p = new HttpParams().set('classId', classId);
    if (sectionId) p = p.set('sectionId', sectionId);
    return this.http
      .get<ApiResponse<ItemsData<TimetableSlot>>>(this.base, { params: p })
      .pipe(map((r) => r.data?.items ?? []));
  }

  /** The signed-in student's own class timetable + the class's period structure. */
  mine(): Observable<MyTimetable> {
    return this.http
      .get<ApiResponse<MyTimetable>>(`${this.base}/mine`)
      .pipe(map((r) => ({ items: r.data?.items ?? [], schedule: r.data?.schedule ?? [] })));
  }

  /** Period / break / lunch structure of a class (empty = not configured yet). */
  schedule(classId: number): Observable<PeriodScheduleItem[]> {
    const p = new HttpParams().set('classId', classId);
    return this.http
      .get<ApiResponse<ItemsData<PeriodScheduleItem>>>(`${this.base}/schedule`, { params: p })
      .pipe(map((r) => r.data?.items ?? []));
  }

  saveSchedule(classId: number, items: PeriodScheduleItem[]): Observable<ApiResponse<PeriodScheduleSaveResult>> {
    return this.http.put<ApiResponse<PeriodScheduleSaveResult>>(`${this.base}/schedule`, {
      ClassId: classId,
      Items: items.map((i) => ({ Kind: i.kind, Label: i.label, StartTime: i.start_time, EndTime: i.end_time }))
    });
  }

  /** Everything one teacher teaches (class, day, time). */
  teacherSchedule(teacherId: number): Observable<TeacherSchedule | null> {
    return this.http
      .get<ApiResponse<TeacherSchedule>>(`${this.base}/teacher/${teacherId}`)
      .pipe(map((r) => r.data));
  }

  save(body: TimetableSlotUpsert): Observable<ApiResponse> {
    return this.http.post<ApiResponse>(this.base, body);
  }

  delete(slotId: number): Observable<ApiResponse> {
    return this.http.delete<ApiResponse>(`${this.base}/${slotId}`);
  }
}
