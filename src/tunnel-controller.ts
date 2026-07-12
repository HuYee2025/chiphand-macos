import * as THREE from "three";
import { advanceContinuousRoll } from "./input-controller";
import type { Point2D } from "./types";

type TunnelSegment = {
  group: THREE.Group;
  seed: number;
  z: number;
  baseRotation: number;
  twist: number;
};

const FRONT_Z = 9.5;
const SEGMENT_SPACING = 2.05;

function seeded(seed: number): number {
  const value = Math.sin(seed * 12.9898) * 43758.5453;
  return value - Math.floor(value);
}

export class TunnelController {
  private readonly scene = new THREE.Scene();
  private readonly camera: THREE.PerspectiveCamera;
  private readonly renderer: THREE.WebGLRenderer;
  private readonly segments: TunnelSegment[];
  private readonly loopLength: number;
  private readonly backZ: number;
  private readonly innerGlow: THREE.PointLight;
  private readonly halo: THREE.Mesh<THREE.RingGeometry, THREE.MeshBasicMaterial>;
  private readonly core: THREE.Mesh<THREE.CircleGeometry, THREE.MeshBasicMaterial>;
  private readonly stars: THREE.Points;
  private steering: Point2D = { x: 0, y: 0 };
  private rollInput = 0;
  private rollAngle = 0;
  private speedScale = 1;
  private paused = false;
  private elapsed = 0;
  private readonly tunnelSpeed = 13.5;

  constructor(private readonly root: HTMLElement) {
    const mobile = window.matchMedia("(max-width: 720px)").matches;
    const segmentCount = mobile ? 42 : 52;
    this.loopLength = segmentCount * SEGMENT_SPACING;
    this.backZ = FRONT_Z - this.loopLength;

    this.scene.background = new THREE.Color(0x050504);
    this.scene.fog = new THREE.FogExp2(0x050504, 0.035);

    this.camera = new THREE.PerspectiveCamera(68, window.innerWidth / window.innerHeight, 0.1, 170);
    this.camera.position.set(0, 0, 15.5);
    this.camera.lookAt(0, 0, -40);

    this.renderer = new THREE.WebGLRenderer({
      antialias: true,
      alpha: false,
      powerPreference: "high-performance",
    });
    this.renderer.outputColorSpace = THREE.SRGBColorSpace;
    this.root.appendChild(this.renderer.domElement);

    this.scene.add(new THREE.AmbientLight(0xd8ccb8, 0.72));
    const keyLight = new THREE.PointLight(0xfff4d0, 85, 64, 1.65);
    keyLight.position.set(-4.5, 5.5, 7);
    this.scene.add(keyLight);
    this.innerGlow = new THREE.PointLight(0x8fb7ff, 42, 88, 1.35);
    this.innerGlow.position.set(0, 0, -42);
    this.scene.add(this.innerGlow);
    const farGlow = new THREE.PointLight(0xffffff, 18, 72, 1.8);
    farGlow.position.set(0, 0, -86);
    this.scene.add(farGlow);

    const materials = {
      ivory: new THREE.MeshStandardMaterial({ color: 0xe8dfca, roughness: 0.68, metalness: 0.04 }),
      bone: new THREE.MeshStandardMaterial({ color: 0xb9b29d, roughness: 0.84, metalness: 0.02 }),
      shadow: new THREE.MeshStandardMaterial({ color: 0x151511, roughness: 0.9, metalness: 0.12 }),
      line: new THREE.MeshStandardMaterial({ color: 0x2f3028, roughness: 0.78, metalness: 0.18 }),
      glint: new THREE.MeshStandardMaterial({
        color: 0xf8f2df,
        emissive: 0x342d20,
        roughness: 0.42,
        metalness: 0.08,
      }),
    };
    const geometry = {
      rib: new THREE.TorusGeometry(7.15, 0.09, 7, 144),
      innerRib: new THREE.TorusGeometry(4.35, 0.055, 6, 112),
      block: new THREE.BoxGeometry(1, 1, 1),
    };

    this.segments = Array.from({ length: segmentCount }, (_, index) =>
      this.makeSegment(index, geometry, materials),
    );

    this.core = new THREE.Mesh(
      new THREE.CircleGeometry(4.2, 96),
      new THREE.MeshBasicMaterial({ color: 0x020202, transparent: true, opacity: 0.9, depthWrite: false }),
    );
    this.core.position.z = -92;
    this.scene.add(this.core);

    this.halo = new THREE.Mesh(
      new THREE.RingGeometry(3.8, 8.2, 160),
      new THREE.MeshBasicMaterial({
        color: 0xc8d4ff,
        transparent: true,
        opacity: 0.12,
        side: THREE.DoubleSide,
        blending: THREE.AdditiveBlending,
        depthWrite: false,
      }),
    );
    this.halo.position.z = -74;
    this.scene.add(this.halo);

    const starGeometry = new THREE.BufferGeometry();
    const positions: number[] = [];
    for (let index = 0; index < 900; index += 1) {
      const seed = index * 4.91;
      const angle = seeded(seed) * Math.PI * 2;
      const radius = 12 + seeded(seed + 1) * 56;
      positions.push(Math.cos(angle) * radius, Math.sin(angle) * radius, -120 + seeded(seed + 2) * 142);
    }
    starGeometry.setAttribute("position", new THREE.Float32BufferAttribute(positions, 3));
    this.stars = new THREE.Points(
      starGeometry,
      new THREE.PointsMaterial({ color: 0xf6eed9, size: 0.035, transparent: true, opacity: 0.5, depthWrite: false }),
    );
    this.scene.add(this.stars);

    window.addEventListener("resize", this.resize);
    this.resize();
  }

  setSteering(steering: Point2D): void {
    this.steering = {
      x: THREE.MathUtils.clamp(steering.x, -1, 1),
      y: THREE.MathUtils.clamp(steering.y, -1, 1),
    };
  }

  setPaused(paused: boolean): void {
    this.paused = paused;
  }

  setRoll(roll: number): void {
    this.rollInput = THREE.MathUtils.clamp(roll, -1, 1);
  }

  setSpeedScale(speedScale: number): void {
    this.speedScale = THREE.MathUtils.clamp(speedScale, 0.45, 2.4);
  }

  isPaused(): boolean {
    return this.paused;
  }

  render(deltaSeconds: number): void {
    const rawDelta = Math.min(deltaSeconds, 0.045);
    const motionDelta = this.paused ? 0 : rawDelta;
    this.elapsed += rawDelta;
    this.rollAngle = advanceContinuousRoll(this.rollAngle, this.rollInput, motionDelta);

    const driftX = Math.sin(this.elapsed * 0.37) * 0.18 + Math.sin(this.elapsed * 0.91) * 0.06;
    const driftY = Math.cos(this.elapsed * 0.31) * 0.14;
    const desiredX = this.steering.x * 1.15 + driftX;
    const desiredY = this.steering.y * 0.92 + driftY;
    this.camera.position.x = THREE.MathUtils.lerp(this.camera.position.x, desiredX, 0.08);
    this.camera.position.y = THREE.MathUtils.lerp(this.camera.position.y, desiredY, 0.08);
    this.camera.lookAt(this.steering.x * 5.2, this.steering.y * 4.1, -48);
    this.camera.rotateZ(-this.steering.x * 0.055 - this.rollInput * 0.08);

    this.innerGlow.intensity = 35 + Math.sin(this.elapsed * 1.7) * 8;
    this.halo.rotation.z -= motionDelta * 0.22;
    this.halo.material.opacity = 0.1 + Math.sin(this.elapsed * 1.3) * 0.025;
    this.core.scale.setScalar(1 + Math.sin(this.elapsed * 1.1) * 0.05);
    this.stars.rotation.z += motionDelta * 0.01;

    for (const segment of this.segments) {
      segment.z += this.tunnelSpeed * this.speedScale * motionDelta;
      if (segment.z > FRONT_Z) {
        segment.z -= this.loopLength;
        segment.baseRotation += Math.PI * 0.618;
      }
      segment.group.position.z = segment.z;
      const depthFactor = THREE.MathUtils.clamp((segment.z - this.backZ) / this.loopLength, 0, 1);
      const pulse = 1 + Math.sin(this.elapsed * 1.4 + segment.seed) * 0.016;
      segment.group.scale.setScalar((0.74 + depthFactor * 0.38) * pulse);
      segment.group.rotation.z =
        segment.baseRotation * 0.08 +
        segment.twist * Math.sin(this.elapsed * 0.4 + segment.seed) +
        this.rollAngle;
    }
    this.renderer.render(this.scene, this.camera);
  }

  private makeSegment(
    index: number,
    geometry: { rib: THREE.TorusGeometry; innerRib: THREE.TorusGeometry; block: THREE.BoxGeometry },
    materials: Record<"ivory" | "bone" | "shadow" | "line" | "glint", THREE.MeshStandardMaterial>,
  ): TunnelSegment {
    const group = new THREE.Group();
    const seed = index * 19.73 + 3.1;
    const z = FRONT_Z - index * SEGMENT_SPACING;
    const baseRotation = seeded(seed) * Math.PI * 2;
    const radiusPulse = 0.72 + seeded(seed + 0.4) * 0.7;
    const ovalX = 1 + (seeded(seed + 1.2) - 0.5) * 0.16;
    const ovalY = 1 + (seeded(seed + 2.2) - 0.5) * 0.18;

    const rib = new THREE.Mesh(geometry.rib, index % 4 === 0 ? materials.glint : materials.bone);
    rib.scale.set(ovalX * (1 + radiusPulse * 0.025), ovalY, 1);
    rib.rotation.z = baseRotation * 0.35;
    group.add(rib);

    if (index % 2 === 0) {
      const innerRib = new THREE.Mesh(geometry.innerRib, materials.shadow);
      innerRib.position.z = -0.18;
      innerRib.scale.set(ovalY * 1.06, ovalX * 0.96, 1);
      innerRib.rotation.z = baseRotation * -0.52;
      group.add(innerRib);
    }

    const panelCount = 14 + Math.floor(seeded(seed + 3.6) * 8);
    for (let panelIndex = 0; panelIndex < panelCount; panelIndex += 1) {
      const localSeed = seed + panelIndex * 5.217;
      const angle = baseRotation + (panelIndex / panelCount) * Math.PI * 2 + (seeded(localSeed) - 0.5) * 0.08;
      const radial = 6.15 + seeded(localSeed + 1) * 2.25;
      const tangential = 0.64 + seeded(localSeed + 2) * 1.42;
      const depth = 0.35 + seeded(localSeed + 3) * 1.05;
      const height = 0.18 + seeded(localSeed + 4) * 0.65;
      const panel = this.createBlock(
        geometry.block,
        seeded(localSeed + 5) > 0.42 ? materials.ivory : materials.shadow,
        new THREE.Vector3(Math.cos(angle) * radial * ovalX, Math.sin(angle) * radial * ovalY, (seeded(localSeed + 6) - 0.5) * 0.44),
        angle,
        new THREE.Vector3(height, tangential, depth),
      );
      panel.rotation.x = (seeded(localSeed + 7) - 0.5) * 0.15;
      panel.rotation.y = (seeded(localSeed + 8) - 0.5) * 0.18;
      group.add(panel);

      if (seeded(localSeed + 9) > 0.36) {
        const insetRadius = radial - 0.32 - seeded(localSeed + 10) * 0.55;
        group.add(
          this.createBlock(
            geometry.block,
            seeded(localSeed + 11) > 0.58 ? materials.line : materials.shadow,
            new THREE.Vector3(Math.cos(angle) * insetRadius * ovalX, Math.sin(angle) * insetRadius * ovalY, 0.27),
            angle,
            new THREE.Vector3(0.05, tangential * 0.54, 0.08),
          ),
        );
      }

      if (panelIndex % 3 === 0) {
        const strutRadius = 5.05 + seeded(localSeed + 12) * 0.65;
        const strut = this.createBlock(
          geometry.block,
          materials.line,
          new THREE.Vector3(Math.cos(angle) * strutRadius * ovalX, Math.sin(angle) * strutRadius * ovalY, -0.18),
          angle + Math.PI * 0.5,
          new THREE.Vector3(0.035, 1.1 + seeded(localSeed + 13) * 1.8, 0.04),
        );
        strut.rotation.y = 0.2 + seeded(localSeed + 14) * 0.38;
        group.add(strut);
      }
    }

    const toothCount = 9 + Math.floor(seeded(seed + 20.4) * 7);
    for (let toothIndex = 0; toothIndex < toothCount; toothIndex += 1) {
      const localSeed = seed + toothIndex * 9.33;
      const angle = baseRotation * 1.7 + (toothIndex / toothCount) * Math.PI * 2;
      const radius = 3.34 + seeded(localSeed + 1) * 0.95;
      const tooth = this.createBlock(
        geometry.block,
        seeded(localSeed + 2) > 0.52 ? materials.ivory : materials.shadow,
        new THREE.Vector3(Math.cos(angle) * radius * ovalX, Math.sin(angle) * radius * ovalY, 0.08),
        angle,
        new THREE.Vector3(0.28 + seeded(localSeed + 3) * 0.56, 0.1, 0.56 + seeded(localSeed + 4) * 0.58),
      );
      tooth.rotation.x = Math.PI * 0.5 + (seeded(localSeed + 5) - 0.5) * 0.14;
      group.add(tooth);
    }

    group.position.z = z;
    this.scene.add(group);
    return { group, seed, z, baseRotation, twist: (seeded(seed + 40.1) - 0.5) * 1.8 };
  }

  private createBlock(
    geometry: THREE.BufferGeometry,
    material: THREE.Material,
    position: THREE.Vector3,
    rotationZ: number,
    scale: THREE.Vector3,
  ): THREE.Mesh {
    const mesh = new THREE.Mesh(geometry, material);
    mesh.position.copy(position);
    mesh.rotation.z = rotationZ;
    mesh.scale.copy(scale);
    return mesh;
  }

  private readonly resize = (): void => {
    const width = window.innerWidth;
    const height = window.innerHeight;
    const mobile = width < 720;
    this.camera.aspect = width / height;
    this.camera.fov = mobile ? 76 : 68;
    this.camera.updateProjectionMatrix();
    this.renderer.setPixelRatio(Math.min(window.devicePixelRatio, mobile ? 1 : 1.35));
    this.renderer.setSize(width, height);
  };
}
