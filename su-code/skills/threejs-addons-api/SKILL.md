---
name: threejs-addons-api
description: Reference for Three.js addons and API—explicit imports, loaders (GLTF, EXR, VTK, PDB, STL, FBX, etc.), exporters (EXR, GLTF), post-processing (BloomNode, FXAA, SMAA, TSL), GPUComputationRenderer, helpers, and core constructors/methods. Use when working with Three.js addons, loaders, exporters, TSL/post-processing, or when the user mentions three.js addons, loaders, or specific Three.js APIs.
---

# Three.js Addons & API Reference

Three.js addons (loaders, exporters, helpers, post-processing, TSL nodes) must be imported explicitly. Core patterns and representative APIs are below; full API snippets are in [reference.md](reference.md).

## When to Use

- **Addons**: Loaders, exporters, helpers, controls, post-processing, TSL nodes—all from `three/addons/...`.
- **Loaders**: GLTFLoader, EXRLoader, VTKLoader, PDBLoader, STLLoader, FBXLoader, DRACOLoader, KTX2Loader, etc.
- **Exporters**: EXRExporter, GLTFExporter, OBJExporter, KTX2Exporter.
- **Post-processing / TSL**: BloomNode, pass, mrt, PostProcessing, FXAA, SMAA, SSSNode, ToneMappingNode.
- **GPU compute**: GPUComputationRenderer (createTexture, addVariable, setVariableDependencies, init, compute).
- **Helpers**: CameraHelper, SpotLightHelper, PointLightHelper, Box3Helper, SkeletonHelper, etc.
- **Core**: Scene, Camera, Light, Mesh, BufferGeometry, Materials, Uniforms, Color, etc.

## Addon Import Pattern

All addons require explicit import. Never assume they are on `THREE` or `three`.

```javascript
// Loaders
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';
import { EXRLoader } from 'three/addons/loaders/EXRLoader.js';
import { DRACOLoader } from 'three/addons/loaders/DRACOLoader.js';
import { PDBLoader } from 'three/addons/loaders/PDBLoader.js';
import { STLLoader } from 'three/addons/loaders/STLLoader.js';
import { FBXLoader } from 'three/addons/loaders/FBXLoader.js';
import { VTKLoader } from 'three/addons/loaders/VTKLoader.js';

// Exporters
import { EXRExporter } from 'three/addons/exporters/EXRExporter.js';
import { GLTFExporter } from 'three/addons/exporters/GLTFExporter.js';

// Helpers
import { LightProbeHelper } from 'three/addons/helpers/LightProbeHelper.js';
import { OctreeHelper } from 'three/addons/helpers/OctreeHelper.js';

// Post-processing / TSL
import { bloom } from 'three/addons/tsl/display/BloomNode.js';
import { fxaa } from 'three/addons/tsl/display/FXAANode.js';
import { smaa } from 'three/addons/tsl/display/SMAANode.js';

// Misc
import { GPUComputationRenderer } from 'three/addons/misc/GPUComputationRenderer.js';
import { OrbitControls } from 'three/addons/controls/OrbitControls.js';
```

## Loaders Pattern

- **Constructor**: `new Loader( manager? )` — optional LoadingManager.
- **Load**: `loader.load( url, onLoad?, onProgress?, onError? )` or `await loader.loadAsync( url )`.
- **Parse**: Many loaders have `loader.parse( data )` for raw buffer/string.
- **Optional setup**: e.g. DRACOLoader `setDecoderPath`, KTX2Loader `setTranscoderPath`, `detectSupport( renderer )`.

```javascript
// GLTF with Draco
const loader = new GLTFLoader();
const dracoLoader = new DRACOLoader();
dracoLoader.setDecoderPath( '/examples/jsm/libs/draco/' );
loader.setDRACOLoader( dracoLoader );
const gltf = await loader.loadAsync( 'models/gltf/duck/duck.gltf' );
scene.add( gltf.scene );

// EXR texture
const exrLoader = new EXRLoader();
const texture = await exrLoader.loadAsync( 'textures/memorial.exr' );

// STL geometry
const stlLoader = new STLLoader();
const geometry = await stlLoader.loadAsync( './models/stl/slotted_disk.stl' );
scene.add( new THREE.Mesh( geometry, material ) );

// PDB (atoms/bonds)
const pdbLoader = new PDBLoader();
const pdb = await pdbLoader.loadAsync( 'models/pdb/ethanol.pdb' );
const geometryAtoms = pdb.geometryAtoms;
const geometryBonds = pdb.geometryBonds;
```

## Exporters Pattern

- **Constructor**: `new Exporter()` (no args typically).
- **Parse**: `exporter.parse( input, options )` or `await exporter.parseAsync( input, options )`.
- **EXR**: input is renderer; **GLTF**: input is scene (or array of scenes).

```javascript
// EXR
const exporter = new EXRExporter();
const result = await exporter.parse( renderer, options );

// GLTF
const exporter = new GLTFExporter();
const data = await exporter.parseAsync( scene, options );
```

## Post-Processing & TSL

- **PostProcessing**: `new THREE.PostProcessing( renderer )`, set `outputNode`.
- **Scene pass**: `pass( scene, camera )`; optional MRT: `scenePass.setMRT( mrt( { output, emissive } ) )`.
- **Bloom**: `bloom( scenePassColor )` or `bloom( emissivePass )` for selective bloom; combine with `scenePassColor.add( bloomPass )`.
- **FXAA / SMAA**: apply to texture node before sRGB; use `getTextureNode()` for result.

```javascript
// Basic bloom (full scene)
const postProcessing = new THREE.PostProcessing( renderer );
const scenePass = pass( scene, camera );
const scenePassColor = scenePass.getTextureNode( 'output' );
const bloomPass = bloom( scenePassColor );
postProcessing.outputNode = scenePassColor.add( bloomPass );

// Bloom with MRT (emissive only)
scenePass.setMRT( mrt( { output, emissive } ) );
const emissivePass = scenePass.getTextureNode( 'emissive' );
const bloomPass = bloom( emissivePass );
postProcessing.outputNode = scenePassColor.add( bloomPass );
```

## GPUComputationRenderer

- **Import**: `import { GPUComputationRenderer } from 'three/addons/misc/GPUComputationRenderer.js';`
- **Create**: `new GPUComputationRenderer( sizeX, sizeY, renderer )`.
- **Textures**: `createTexture()`; fill with data then use as initial value.
- **Variables**: `addVariable( name, fragmentShader, initialTexture )`; `setVariableDependencies( variable, [ dependencies ] )`.
- **Init**: `const error = gpuCompute.init();` — check for `null`.
- **Per frame**: `gpuCompute.compute();` then use `getCurrentRenderTarget( variable ).texture` for materials.

```javascript
const gpuCompute = new GPUComputationRenderer( 1024, 1024, renderer );
const pos0 = gpuCompute.createTexture();
const vel0 = gpuCompute.createTexture();
// fill textures...
const velVar = gpuCompute.addVariable( 'textureVelocity', fragmentShaderVel, vel0 );
const posVar = gpuCompute.addVariable( 'texturePosition', fragmentShaderPos, pos0 );
gpuCompute.setVariableDependencies( velVar, [ velVar, posVar ] );
gpuCompute.setVariableDependencies( posVar, [ velVar, posVar ] );
const error = gpuCompute.init();
if ( error !== null ) console.error( error );
// In render loop:
gpuCompute.compute();
myMaterial.uniforms.myTexture.value = gpuCompute.getCurrentRenderTarget( posVar ).texture;
```

## Helpers Pattern

- **Constructor**: typically `new Helper( objectToVisualize, size?, color? )`.
- **Add to scene**: `scene.add( helper )` (or as child of the object, e.g. PositionalAudioHelper as child of audio).
- **Update**: many helpers have `helper.update()` each frame.

```javascript
const light = new THREE.SpotLight( 0xffffff );
light.position.set( 10, 10, 10 );
scene.add( light );
const spotLightHelper = new THREE.SpotLightHelper( light );
scene.add( spotLightHelper );
// In loop: spotLightHelper.update();

const helper = new THREE.CameraHelper( camera );
scene.add( helper );
```

## Core Snippets

- **Scene**: `scene.background`, `scene.environment`, `scene.fog` (Fog or FogExp2).
- **AmbientLight**: `new THREE.AmbientLight( 0x404040 ); scene.add( light );`
- **Color**: `new THREE.Color( 0xff0000 )`, `setHex`, `setRGB`, `setColorName`, `toArray`.
- **InstancedMesh**: `new THREE.InstancedMesh( geometry, material, count )`; `setMatrixAt( index, matrix )`, `setColorAt( index, color )`; set `instanceMatrix.needsUpdate = true`.
- **BufferGeometry**: `setAttribute`, `getAttribute`, `deleteAttribute`, `setIndex`, `clearGroups`.
- **Renderer**: `setAnimationLoop( callback )`, `initTexture( texture )` / `initTextureAsync( texture )` for preload.

## Summary

1. **Addons**: Always import from `three/addons/...`; never rely on global THREE for addons.
2. **Loaders**: `load`/`loadAsync`, optional `parse`; configure decoders (Draco, KTX2) when needed.
3. **Exporters**: `parse`/`parseAsync` with renderer (EXR) or scene (GLTF).
4. **Post-processing**: Pass node → getTextureNode → effects (bloom, fxaa, smaa) → outputNode.
5. **GPU compute**: addVariable, setVariableDependencies, init, compute; read texture from getCurrentRenderTarget.
6. **Helpers**: Instantiate with target object, add to scene, call update() when needed.

For detailed method signatures, constructors, and more APIs, see [reference.md](reference.md).
