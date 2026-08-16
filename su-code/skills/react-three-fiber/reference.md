# React Three Fiber — Reference

Additional patterns: test renderer, React Native, portals, frameloop control, render-to-texture.

## Test Renderer

Test R3F components in Node with `@react-three/test-renderer`.

```jsx
import { create, act, waitFor } from '@react-three/test-renderer'
import { useFrame } from '@react-three/fiber'

function AnimatedBox() {
  const meshRef = useRef()
  useFrame((state, delta) => { meshRef.current.rotation.x += delta })
  return (
    <mesh ref={meshRef} onClick={() => setScale(2)}>
      <boxGeometry args={[1, 1, 1]} />
      <meshBasicMaterial color="red" />
    </mesh>
  )
}

const renderer = await create(<AnimatedBox />)
const mesh = renderer.scene.findByType('Mesh')
await renderer.advanceFrames(60, 1/60)
await act(async () => { renderer.fireEvent(mesh, 'onClick') })
await renderer.update(<AnimatedBox />)
const tree = renderer.toTree()
const graph = renderer.toGraph()
await renderer.unmount()
```

Async: `await waitFor(() => renderer.scene.findByType('Mesh'), { timeout: 200, interval: 10 })`.

## React Native

Use `@react-three/fiber/native` with Expo GL. Load assets via `Asset.fromModule(require('./assets/tex.png')).uri` and `useLoader(TextureLoader, uri)`.

```jsx
import { Canvas } from '@react-three/fiber/native'
import { useLoader } from '@react-three/fiber'
import { TextureLoader } from 'three'
import { Asset } from 'expo-asset'
import { Suspense } from 'react'

function Model() {
  const texture = useLoader(
    TextureLoader,
    Asset.fromModule(require('./assets/texture.png')).uri
  )
  return (
    <mesh>
      <planeGeometry args={[2, 2]} />
      <meshBasicMaterial map={texture} />
    </mesh>
  )
}

export default function App() {
  return (
    <Canvas camera={{ position: [0, 0, 5], fov: 75 }} gl={{ preserveDrawingBuffer: true }}>
      <ambientLight intensity={0.5} />
      <Suspense fallback={null}>
        <Model />
      </Suspense>
      <mesh rotation={[0, Math.PI / 4, 0]}>
        <boxGeometry args={[1, 1, 1]} />
        <meshStandardMaterial color="orange" />
      </mesh>
    </Canvas>
  )
}
```

Metro: add `assetExts: ['glb', 'gltf', 'png', 'jpg']` and `sourceExts` as needed.

## Advanced Patterns

### Portal (render to texture)

Use `createPortal` to render into a virtual scene, then render that scene to an FBO and use the texture.

```jsx
import { createPortal, useFrame, useThree } from '@react-three/fiber'
import { useFBO } from '@react-three/drei'
import { useMemo } from 'react'
import * as THREE from 'three'

function RenderToTexture() {
  const { gl } = useThree()
  const fbo = useFBO(1024, 1024)
  const virtualScene = useMemo(() => new THREE.Scene(), [])
  const virtualCamera = useMemo(() => new THREE.PerspectiveCamera(75, 1, 0.1, 100), [])

  useFrame(() => {
    gl.setRenderTarget(fbo)
    gl.render(virtualScene, virtualCamera)
    gl.setRenderTarget(null)
  })

  return (
    <>
      {createPortal(
        <mesh><sphereGeometry args={[1, 32, 32]} /><meshStandardMaterial color="red" /></mesh>,
        virtualScene
      )}
      <mesh>
        <planeGeometry args={[4, 4]} />
        <meshBasicMaterial map={fbo.texture} />
      </mesh>
    </>
  )
}
```

### Frameloop control

```jsx
const { setFrameloop } = useThree((state) => ({ setFrameloop: state.setFrameloop }))
setFrameloop('always')   // default
setFrameloop('demand')   // render only when invalidate() is called
setFrameloop('never')    // manual only via advance()
```

### Manual render loop

```jsx
const { advance, invalidate } = useThree((state) => ({
  advance: state.advance,
  invalidate: state.invalidate
}))
// One frame: advance(performance.now())
// On demand: invalidate() or invalidate(60)
```

### Performance regression

```jsx
const { performance, invalidate } = useThree((state) => ({
  performance: state.performance,
  invalidate: state.invalidate
}))
performance.regress()   // signal drop; R3F may switch to continuous render
invalidate(120)         // force next 120 frames (e.g. 2s at 60fps)
```

## useLoader — Extensions and progress

```jsx
const gltf = useLoader(
  GLTFLoader,
  '/scene.glb',
  (loader) => {
    const draco = new DRACOLoader()
    draco.setDecoderPath('/draco/')
    loader.setDRACOLoader(draco)
  },
  (progress) => console.log((progress.loaded / progress.total) * 100, '%')
)
```

## extend — Multiple classes and custom class

```jsx
import { extend } from '@react-three/fiber'
import { EffectComposer, RenderPass } from 'three/examples/jsm/postprocessing/...'

extend({ EffectComposer, RenderPass })

class CustomHelper extends THREE.LineSegments { ... }
extend({ CustomHelper })

// JSX: <effectComposer>, <renderPass attach="passes" args={[scene, camera]} />, <customHelper args={[5]} />
```

Declare in TypeScript: `JSX.IntrinsicElements.customHelper: ReactThreeFiber.Object3DNode<CustomHelper, typeof CustomHelper>`.
