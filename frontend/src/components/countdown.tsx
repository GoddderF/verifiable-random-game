"use client";

import { useEffect, useState } from "react";
import { Badge } from "@/components/ui/badge";

type Props = {
  endTimestamp: bigint;
  label?: string;
};

export function Countdown({ endTimestamp, label = "剩余时间" }: Props) {
  const [remaining, setRemaining] = useState<number | null>(null);

  useEffect(() => {
    const tick = () => {
      const end = Number(endTimestamp) * 1000;
      setRemaining(Math.max(0, end - Date.now()));
    };
    tick();
    const id = setInterval(tick, 1000);
    return () => clearInterval(id);
  }, [endTimestamp]);

  if (remaining === null) return null;

  const totalSec = Math.floor(remaining / 1000);
  const h = Math.floor(totalSec / 3600);
  const m = Math.floor((totalSec % 3600) / 60);
  const s = totalSec % 60;
  const text = `${h.toString().padStart(2, "0")}:${m.toString().padStart(2, "0")}:${s.toString().padStart(2, "0")}`;

  return (
    <div className="flex items-center gap-2">
      <span className="text-sm text-slate-400">{label}</span>
      <Badge variant={remaining === 0 ? "warning" : "default"} className="font-mono text-base">
        {remaining === 0 ? "已结束" : text}
      </Badge>
    </div>
  );
}
