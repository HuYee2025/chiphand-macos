import type { HandControlState } from "./types";

const HAND_COLORS = {
  Left: "#ff4555",
  Right: "#3f8cff",
} as const;

const HAND_CONNECTIONS = [
  [0, 1], [1, 2], [2, 3], [3, 4],
  [0, 5], [5, 6], [6, 7], [7, 8],
  [5, 9], [9, 10], [10, 11], [11, 12],
  [9, 13], [13, 14], [14, 15], [15, 16],
  [13, 17], [17, 18], [18, 19], [19, 20], [0, 17],
] as const;

export class CameraOverlay {
  private readonly context: CanvasRenderingContext2D;

  constructor(
    private readonly video: HTMLVideoElement,
    private readonly canvas: HTMLCanvasElement,
  ) {
    const context = this.canvas.getContext("2d");
    if (!context) throw new Error("无法创建手部关键点画布。");
    this.context = context;
  }

  draw(state: HandControlState): void {
    const width = this.video.videoWidth || 640;
    const height = this.video.videoHeight || 480;
    if (this.canvas.width !== width || this.canvas.height !== height) {
      this.canvas.width = width;
      this.canvas.height = height;
    }
    this.context.clearRect(0, 0, width, height);
    if (!state.detected || state.landmarks.length === 0) return;

    const color = state.handedness ? HAND_COLORS[state.handedness] : "#f1ead9";
    this.context.lineCap = "round";
    this.context.lineJoin = "round";
    this.context.strokeStyle = color;
    this.context.lineWidth = Math.max(2, width * 0.004);
    this.context.globalAlpha = 0.82;

    for (const [startIndex, endIndex] of HAND_CONNECTIONS) {
      const start = state.landmarks[startIndex];
      const end = state.landmarks[endIndex];
      if (!start || !end) continue;
      this.context.beginPath();
      this.context.moveTo(start.x * width, start.y * height);
      this.context.lineTo(end.x * width, end.y * height);
      this.context.stroke();
    }

    this.context.globalAlpha = 1;
    for (const [index, landmark] of state.landmarks.entries()) {
      const radius = index === 0 || [5, 9, 13, 17].includes(index) ? width * 0.009 : width * 0.006;
      this.context.beginPath();
      this.context.arc(landmark.x * width, landmark.y * height, Math.max(2.5, radius), 0, Math.PI * 2);
      this.context.fillStyle = index === 0 ? "#f1ead9" : color;
      this.context.fill();
    }
  }
}
