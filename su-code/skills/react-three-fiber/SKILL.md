---
name: react-three-fiber
description: Reference for React Three Fiber (R3F)—declarative Three.js in React. Covers Canvas, useFrame, useThree, useLoader, JSX elements, pointer events, applyProps, extend, testing, and React Native. Use when building 3D scenes in React, using @react-three/fiber, integrating Three.js with React, or when the user mentions R3F, react-three-fiber, or 3D graphics in React.
---

# React Three Fiber

React Three Fiber is a React renderer for Three.js: declarative 3D in React with JSX, hooks, and state. Zero-overhead reconciler; full Three.js API; supports web and React Native.

## When to Use

- **Canvas & scene**: `<Canvas>`, camera, lights, shadows, `onCreated`, `dpr`, `gl`.
- **Animation**: `useFrame(state, delta)` for per-frame updates and game loops.
- **State**: `useThree()` for renderer, scene, camera, viewport, `invalidate`, `setSize`.
- **Assets**: `useLoader` with Suspense, preload/clear, progress callbacks.
- **JSX**: mesh, geometries, materials, lights, `group`, `primitive`, `attach`.
- **Interaction**: `onClick`, `onPointerOver`/`Out`, `onPointerMove`, raycasting, `event.point`.
- **Imperative**: `applyProps`, `extend` for custom/custom Three.js classes.
- **Advanced**: portals, frameloop control, render-to-texture, testing, React Native — see [reference.md](reference.md).

## Canvas

Creates WebGL context, scene, camera, and renderer.

```jsx
import { Canvas } from '@react-three/fiber'

function App() {
  return (
    <Canvas
      camera={{ position: [0, 0, 5], fov: 75 }}
      shadows
      dpr={[1, 2]}
      gl={{ antialias: true }}
      onCreated={({ gl, scene, camera }) => console.log('Ready', gl, scene, camera)}
    >
      <ambientLight intensity={0.5} />
      <spotLight position={[10, 10, 10]} angle={0.3} penumbra={1} />
      <mesh onClick={(e) => console.log(e.point)}>
        <boxGeometry args={[1, 1, 1]} />
        <meshStandardMaterial color="orange" />
      </mesh>
    </Canvas>
  )
}
```

## useFrame

Subscribe to the render loop. Callback receives `(state, delta)`. Use `state.clock`, `state.camera`, `state.gl`, etc. Second argument is render priority (positive = manual control).

```jsx
import { useFrame } from '@react-three/fiber'
import { useRef } from 'react'

function RotatingBox() {
  const meshRef = useRef()

  useFrame((state, delta) => {
    meshRef.current.rotation.x += delta
    meshRef.current.rotation.y += delta * 0.5
    meshRef.current.position.y = Math.sin(state.clock.elapsedTime) * 2
  })

  return (
    <mesh ref={meshRef}>
      <boxGeometry args={[1, 1, 1]} />
      <meshStandardMaterial color="blue" />
    </mesh>
  )
}
```

## useThree

Access renderer, scene, camera, size, viewport. Use a selector for performance: `useThree((state) => state.clock)` so the component only re-renders when that slice changes.

```jsx
import { useThree } from '@react-three/fiber'

function CameraController() {
  const { camera, gl, size, viewport } = useThree()
  // gl.setClearColor, camera.position.set, etc.
  return null
}

function Info() {
  const invalidate = useThree((state) => state.invalidate)
  const setSize = useThree((state) => state.setSize)
  // invalidate() = next frame; invalidate(60) = next 60 frames
  return null
}
```

## useLoader

Load assets with Three.js loaders; integrates with React Suspense. Third arg = config callback, fourth = progress.

```jsx
import { useLoader } from '@react-three/fiber'
import { Suspense } from 'react'
import { GLTFLoader } from 'three/examples/jsm/loaders/GLTFLoader'
import { TextureLoader } from 'three'

function Model() {
  const gltf = useLoader(GLTFLoader, '/models/robot.glb')
  return <primitive object={gltf.scene} />
}

function TexturedMesh() {
  const [color, normal] = useLoader(TextureLoader, ['/color.jpg', '/normal.jpg'])
  return (
    <mesh>
      <planeGeometry args={[5, 5]} />
      <meshStandardMaterial map={color} normalMap={normal} />
    </mesh>
  )
}

// Preload / clear cache
useLoader.preload(GLTFLoader, '/heavy.glb')
useLoader.clear(GLTFLoader, '/heavy.glb')

function App() {
  return (
    <Canvas>
      <Suspense fallback={<mesh><sphereGeometry /><meshBasicMaterial wireframe /></mesh>}>
        <Model />
      </Suspense>
    </Canvas>
  )
}
```

## Three.js as JSX

Use Three.js types as JSX. Geometries take `args={[]}` for constructor params. Use `attach` for nested props (e.g. texture on material). Use `primitive` for existing Three.js objects.

```jsx
<mesh position={[0, 0, 0]}>
  <boxGeometry args={[1, 1, 1]} />
  <meshStandardMaterial color="orange" />
</mesh>

<perspectiveCamera makeDefault position={[0, 5, 10]} fov={75} near={0.1} far={1000} />

<directionalLight position={[5, 5, 5]} intensity={1} castShadow shadow-mapSize={[2048, 2048]} />

<group rotation={[0, Math.PI / 4, 0]} scale={1.5}>
  <mesh position={[-1, 0, 0]}>
    <sphereGeometry args={[0.5, 32, 32]} />
    <meshPhongMaterial color="#ff0000" />
  </mesh>
</group>

<mesh>
  <meshStandardMaterial>
    <texture attach="map" image="/texture.jpg" />
  </meshStandardMaterial>
</mesh>

<primitive object={new THREE.AxesHelper(5)} />
```

## Event Handling

Pointer events on meshes: `onClick`, `onPointerOver`, `onPointerOut`, `onPointerMove`, `onPointerDown`/`Up`, `onContextMenu`, `onDoubleClick`, `onWheel`. Use `event.stopPropagation()`. `event.point` (Vector3), `event.object`, `event.faceIndex`, `event.uv`, `event.distance`, `event.pointer` (normalized). Canvas: `onPointerMissed`.

```jsx
function InteractiveCube() {
  const [hovered, setHovered] = useState(false)

  return (
    <mesh
      onClick={(e) => e.stopPropagation()}
      onPointerOver={() => { setHovered(true); document.body.style.cursor = 'pointer' }}
      onPointerOut={() => { setHovered(false); document.body.style.cursor = 'default' }}
      scale={hovered ? 1.2 : 1}
    >
      <boxGeometry args={[1, 1, 1]} />
      <meshStandardMaterial color={hovered ? 'lightblue' : 'orange'} />
    </mesh>
  )
}
```

## applyProps

Apply props to Three.js objects imperatively. Use dashed paths for nested props: `'material-color'`, `'material-emissiveIntensity'`. Methods: `'position-x'`, `'rotation-setFromVector3': [vec]`.

```jsx
import { applyProps } from '@react-three/fiber'
import { useEffect, useRef } from 'react'

function DynamicMesh() {
  const meshRef = useRef()

  useEffect(() => {
    applyProps(meshRef.current, {
      position: [1, 2, 3],
      rotation: [0, Math.PI / 2, 0],
      scale: 1.5,
      visible: true,
      castShadow: true
    })
    applyProps(meshRef.current.material, { color: '#ff0000', opacity: 0.8 })
  }, [])

  return (
    <mesh ref={meshRef}>
      <boxGeometry />
      <meshStandardMaterial />
    </mesh>
  )
}
```

## extend

Register custom or third-party Three.js classes for JSX. Element names become camelCase: `OrbitControls` → `<orbitControls />`.

```jsx
import { extend } from '@react-three/fiber'
import { OrbitControls } from 'three/examples/jsm/controls/OrbitControls'

extend({ OrbitControls })

function Scene() {
  const { camera, gl } = useThree()
  return <orbitControls args={[camera, gl.domElement]} />
}
```

TypeScript: declare custom elements on `JSX.IntrinsicElements` with `ReactThreeFiber.Object3DNode<YourClass, typeof YourClass>`.

## Summary

- **Canvas**: scene setup, camera, shadows, `onCreated`, `dpr`, `gl`.
- **useFrame**: animation and game loop; optional priority for manual render.
- **useThree**: renderer/scene/camera/size/viewport; use selectors to avoid unnecessary re-renders.
- **useLoader**: load GLTF/textures with Suspense; preload/clear for cache.
- **JSX**: mesh, geometry `args`, lights, `group`, `primitive`, `attach` for nested props.
- **Events**: pointer events on meshes; `event.point`, `event.object`; `onPointerMissed` on Canvas.
- **applyProps**: imperative updates; dashed paths for nested and method calls.
- **extend**: expose custom/third-party classes as JSX components.

For test renderer, React Native, portals, frameloop control, and render-to-texture, see [reference.md](reference.md).
