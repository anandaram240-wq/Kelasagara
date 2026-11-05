// backend/src/services/quota_monitor.ts
/**
 * Firestore Spark Tier Quota & Load Monitor (Ticket T-15).
 * Protects against denial-of-wallet and unexpected Spark free-tier exhaustion.
 * Free limits: 50k reads/day, 20k writes/day, 20k deletes/day.
 */

export interface DailyQuotaUsage {
  reads: number;
  writes: number;
  deletes: number;
  dateStr: string; // YYYY-MM-DD
}

export type QuotaAlarmLevel = "NORMAL" | "WARNING" | "CRITICAL" | "THROTTLED";

export class QuotaMonitorService {
  // Spark Daily Limits
  public static readonly SPARK_READ_LIMIT = 50000;
  public static readonly SPARK_WRITE_LIMIT = 20000;
  public static readonly SPARK_DELETE_LIMIT = 20000;

  private static currentDay: string = new Date().toISOString().substring(0, 10);
  private static usage: DailyQuotaUsage = {
    reads: 0,
    writes: 0,
    deletes: 0,
    dateStr: QuotaMonitorService.currentDay,
  };

  private static checkDateRollover(): void {
    const today = new Date().toISOString().substring(0, 10);
    if (today !== this.currentDay) {
      this.currentDay = today;
      this.usage = { reads: 0, writes: 0, deletes: 0, dateStr: today };
    }
  }

  static recordOperation(reads = 0, writes = 0, deletes = 0): void {
    this.checkDateRollover();
    this.usage.reads += reads;
    this.usage.writes += writes;
    this.usage.deletes += deletes;
  }

  static getUsage(): DailyQuotaUsage {
    this.checkDateRollover();
    return { ...this.usage };
  }

  static getAlarmLevel(): QuotaAlarmLevel {
    this.checkDateRollover();
    const readFraction = this.usage.reads / this.SPARK_READ_LIMIT;
    const writeFraction = this.usage.writes / this.SPARK_WRITE_LIMIT;
    const maxFraction = Math.max(readFraction, writeFraction);

    if (maxFraction >= 0.95) return "THROTTLED";
    if (maxFraction >= 0.85) return "CRITICAL";
    if (maxFraction >= 0.70) return "WARNING";
    return "NORMAL";
  }

  /**
   * Asserts whether a batch read operation of requested size is safe to proceed.
   * Throws error if quota level is THROTTLED.
   */
  static assertSafeToRead(count = 1): void {
    const level = this.getAlarmLevel();
    if (level === "THROTTLED") {
      throw new Error(
        `[QuotaMonitorService] Spark tier read limit exceeded (95%+ of 50,000 reads used). Operation throttled to protect database availability.`
      );
    }
    this.recordOperation(count, 0, 0);
  }

  static resetForTesting(): void {
    this.usage = { reads: 0, writes: 0, deletes: 0, dateStr: this.currentDay };
  }
}
