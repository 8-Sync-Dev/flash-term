# Three.js Addons & API — Reference

Categorized API snippets. Import paths use `three/addons/...`; core APIs use `THREE` or `three`.

---

## Loaders

**GLTFLoader**
```javascript
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';
const loader = new GLTFLoader( manager );
const gltf = await loader.loadAsync( 'models/gltf/duck/duck.gltf' );
loader.setDRACOLoader( dracoLoader );
loader.setKTX2Loader( ktx2Loader );
loader.setMeshoptDecoder( meshoptDecoder );
```

**EXRLoader**
```javascript
import { EXRLoader } from 'three/addons/loaders/EXRLoader.js';
const loader = new EXRLoader( manager );
const texture = await loader.loadAsync( 'textures/memorial.exr' );
loader.setDataType( value );
loader.setOutputFormat( value );
```

**EXRExporter**
```javascript
import { EXRExporter } from 'three/addons/exporters/EXRExporter.js';
const exporter = new EXRExporter();
const result = await exporter.parse( renderer, options );
```

**GLTFExporter**
```javascript
import { GLTFExporter } from 'three/addons/exporters/GLTFExporter.js';
const exporter = new GLTFExporter();
const data = await exporter.parseAsync( scene, options );
```

**DRACOLoader**
```javascript
import { DRACOLoader } from 'three/addons/loaders/DRACOLoader.js';
loader.setDecoderPath( path );
loader.setDecoderConfig( config );
loader.setWorkerLimit( workerLimit );
const geometry = await loader.loadAsync( url );
```

**KTX2Loader**
```javascript
loader.setTranscoderPath( 'examples/jsm/libs/basis/' );
loader.detectSupport( renderer );
const texture = await loader.loadAsync( 'diffuse.ktx2' );
```

**STLLoader**
```javascript
import { STLLoader } from 'three/addons/loaders/STLLoader.js';
const geometry = await loader.loadAsync( './models/stl/slotted_disk.stl' );
loader.parse( data ); // returns BufferGeometry
```

**FBXLoader**
```javascript
import { FBXLoader } from 'three/addons/loaders/FBXLoader.js';
const object = await loader.loadAsync( 'models/fbx/stanford-bunny.fbx' );
scene.add( object );
```

**VTKLoader**
```javascript
import { VTKLoader } from 'three/addons/loaders/VTKLoader.js';
const geometry = await loader.loadAsync( 'models/vtk/liver.vtk' );
geometry.computeVertexNormals();
```

**PDBLoader**
```javascript
import { PDBLoader } from 'three/addons/loaders/PDBLoader.js';
const pdb = await loader.loadAsync( 'models/pdb/ethanol.pdb' );
const geometryAtoms = pdb.geometryAtoms;
const geometryBonds = pdb.geometryBonds;
const json = pdb.json;
```

**XYZLoader**
```javascript
const loader = new XYZLoader();
const geometry = await loader.loadAsync( 'models/xyz/helix_201.xyz' );
geometry.center();
```

**MTLLoader**
```javascript
loader.load( url, onLoad, onProgress, onError );
```

**OBJLoader** — use with MTLLoader for materials.

**PLYLoader, ColladaLoader, GCodeLoader, USDZLoader, ThreeMFLoader, LWOLoader, NRRDLoader, MDDLoader, MD2Loader, TTFLoader, FontLoader, LUTCubeLoader, LUTImageLoader, LUT3dlLoader, KTXLoader, DDSLoader, HDRLoader, UltraHDRLoader, ImageLoader, FileLoader, CubeTextureLoader, DataTextureLoader** — same pattern: constructor(manager?), load/loadAsync, parse when documented.

---

## Post-Processing & TSL

**BloomNode**
```javascript
import { bloom } from 'three/addons/tsl/display/BloomNode.js';
const bloomPass = bloom( scenePassColor );
const bloomPass = bloom( emissivePass ); // selective via MRT
postProcessing.outputNode = scenePassColor.add( bloomPass );
// Constructor: new BloomNode( inputNode, strength?, radius?, threshold? )
// Methods: getTextureNode(), setSize(w,h), dispose(), updateBefore(frame)
```

**Pass & MRT**
```javascript
const scenePass = pass( scene, camera );
const scenePassColor = scenePass.getTextureNode( 'output' );
scenePass.setMRT( mrt( { output, emissive } ) );
const emissivePass = scenePass.getTextureNode( 'emissive' );
```

**FXAANode**
```javascript
import { fxaa } from 'three/addons/tsl/display/FXAANode.js';
// setup( builder ) → ShaderCallNodeInternal
```

**SMAANode**
```javascript
import { smaa } from 'three/addons/tsl/display/SMAANode.js';
// Apply before sRGB. setup( builder ), updateBefore( frame ), getTextureNode(), setSize(w,h), dispose()
```

**PostProcessing**
```javascript
const postProcessing = new THREE.PostProcessing( renderer );
postProcessing.outputNode = scenePassColor.add( bloomPass );
```

**Render output / tone mapping**
```javascript
const outputPass = renderOutput( scenePass );
```

**SSSNode (Screen-Space Shadows)**
```javascript
const sssPass = sss( scenePassDepth, camera, mainLight );
const sssBlur = boxBlur( sssPass.r, { size: 2, separation: 1 } );
```

**SSGINode**
```javascript
new SSGINode( beautyNode, depthNode, normalNode, camera );
// dispose(), getTextureNode(), setSize(w,h), setup(builder), updateBefore(frame)
```

**ToneMappingNode**
```javascript
new ToneMappingNode( toneMapping, exposureNode, colorNode? );
// getToneMapping(), setToneMapping(value)
```

**ClippingNode (TSL)**
```javascript
// .clipping() → ClippingNode (default)
// .clippingAlpha() → ClippingNode (alpha to coverage)
// Methods: setup(builder), setupAlphaToCoverage(intersectionPlanes, unionPlanes), setupDefault(...), setupHardwareClipping(unionPlanes, builder)
```

**LightsNode**
```javascript
// customCacheKey(), getHash(builder), getLights(), setLights(lights), setup(builder), setupDirectLight(builder, lightNode, lightData), setupLights(builder, lightNodes), setupLightsNode(builder)
```

---

## GPU Computation

**GPUComputationRenderer**
```javascript
import { GPUComputationRenderer } from 'three/addons/misc/GPUComputationRenderer.js';
const gpuCompute = new GPUComputationRenderer( sizeX, sizeY, renderer );
const tex = gpuCompute.createTexture();
const variable = gpuCompute.addVariable( name, fragmentShader, initialTexture );
gpuCompute.setVariableDependencies( variable, [ dep1, dep2 ] );
const error = gpuCompute.init();
gpuCompute.compute();
const texture = gpuCompute.getCurrentRenderTarget( variable ).texture;
gpuCompute.getAlternateRenderTarget( variable );
gpuCompute.createRenderTarget();
gpuCompute.createShaderMaterial( fragmentShader, uniforms );
gpuCompute.createTexture();
gpuCompute.dispose();
```

---

## Helpers

**CameraHelper**
```javascript
const helper = new THREE.CameraHelper( camera );
scene.add( helper );
helper.update();
helper.setColors( frustum, cone, up, target, cross );
helper.dispose();
```

**SpotLightHelper**
```javascript
const spotLightHelper = new THREE.SpotLightHelper( spotLight, color? );
scene.add( spotLightHelper );
spotLightHelper.update();
spotLightHelper.dispose();
```

**PointLightHelper**
```javascript
const pointLightHelper = new THREE.PointLightHelper( light, sphereSize?, color? );
scene.add( pointLightHelper );
pointLightHelper.update();
pointLightHelper.dispose();
```

**DirectionalLightHelper**
```javascript
const helper = new THREE.DirectionalLightHelper( light, size );
scene.add( helper );
```

**Box3Helper**
```javascript
const helper = new THREE.Box3Helper( box, color? );
scene.add( helper );
```

**OctreeHelper**
```javascript
import { OctreeHelper } from 'three/addons/helpers/OctreeHelper.js';
const helper = new OctreeHelper( octree );
scene.add( helper );
```

**LightProbeHelper**
```javascript
import { LightProbeHelper } from 'three/addons/helpers/LightProbeHelper.js';
const helper = new LightProbeHelper( lightProbe, size? );
scene.add( helper );
```

**ShadowMapViewer**
```javascript
const viewer = new ShadowMapViewer( light );
viewer.position.x = 10;
viewer.size.width = SHADOW_MAP_WIDTH / 4;
viewer.size.height = SHADOW_MAP_HEIGHT / 4;
viewer.update();
```

**SkeletonHelper**
```javascript
const helper = new THREE.SkeletonHelper( skinnedMesh );
scene.add( helper );
```

**GridHelper**
```javascript
const gridHelper = new THREE.GridHelper( size, divisions );
scene.add( gridHelper );
```

**ArrowHelper**
```javascript
const arrowHelper = new THREE.ArrowHelper( dir, origin, length, hex );
scene.add( arrowHelper );
```

---

## Core

**Scene**
```javascript
const scene = new THREE.Scene();
scene.background = colorOrTexture;
scene.environment = texture;
scene.fog = new THREE.Fog( color, near, far );
scene.fog = new THREE.FogExp2( color, density );
scene.overrideMaterial = material;
```

**AmbientLight**
```javascript
const light = new THREE.AmbientLight( 0x404040 );
scene.add( light );
```

**SpotLight**
```javascript
const spotLight = new THREE.SpotLight( 0xffffff );
spotLight.position.set( 100, 1000, 100 );
spotLight.castShadow = true;
spotLight.shadow.mapSize.width = 1024;
spotLight.shadow.camera.near = 500;
spotLight.shadow.camera.far = 4000;
spotLight.shadow.camera.fov = 30;
```

**Color**
```javascript
const color = new THREE.Color();
const color2 = new THREE.Color( 0xff0000 );
color.setHex( 0x112233 );
color.setRGB( 0.5, 0.5, 0.5 );
color.setColorName( 'skyblue' );
color.toArray( array, offset );
THREE.ColorConverter.getHSV( color, target );
THREE.ColorConverter.setHSV( color, h, s, v );
```

**InstancedMesh**
```javascript
const mesh = new THREE.InstancedMesh( geometry, material, count );
mesh.setMatrixAt( index, matrix );
mesh.setColorAt( index, color );
mesh.instanceMatrix.needsUpdate = true;
mesh.instanceColor.needsUpdate = true;
mesh.getMatrixAt( index, matrix );
mesh.getColorAt( index, color );
```

**BufferGeometry**
```javascript
geometry.setAttribute( name, attribute );
geometry.getAttribute( name );
geometry.deleteAttribute( name );
geometry.setIndex( index );
geometry.clearGroups();
geometry.addGroup( start, count, materialIndex );
```

**FogExp2**
```javascript
scene.fog = new THREE.FogExp2( 0xcccccc, 0.002 );
// .color, .density, .clone(), .toJSON()
```

**Lut**
```javascript
import { Lut } from 'three/addons/math/Lut.js';
const lut = new Lut( 'rainbow', 512 );
const color = lut.getColor( 0.5 );
```

**Audio / PositionalAudio**
```javascript
const listener = new THREE.AudioListener();
camera.add( listener );
const sound = new THREE.Audio( listener );
audioLoader.load( 'sounds/ambient.ogg', ( buffer ) => {
  sound.setBuffer( buffer );
  sound.setLoop( true );
  sound.setVolume( 0.5 );
  sound.play();
});
```

**Renderer**
```javascript
renderer.setAnimationLoop( callback );
renderer.initTexture( texture );
renderer.initTextureAsync( texture );
```

**PerspectiveCamera**
```javascript
camera.setViewOffset( fullWidth, fullHeight, x, y, width, height );
camera.clearViewOffset();
camera.getEffectiveFOV();
camera.getFocalLength();
camera.setFocalLength( focalLength );
```

**OrbitControls**
```javascript
import { OrbitControls } from 'three/addons/controls/OrbitControls.js';
const controls = new OrbitControls( camera, gl.domElement );
controls.getAzimuthalAngle();
controls.getPolarAngle();
controls.getDistance();
controls.reset();
controls.saveState();
controls.listenToKeyEvents( domElement );
controls.mouseButtons = { ONE: THREE.TOUCH.ROTATE, TWO: THREE.TOUCH.DOLLY_PAN };
```

---

## Node Materials & TSL Nodes

**MeshPhongNodeMaterial**: setupEnvironment(builder), setupLightingModel() → PhongLightingModel, setupVariants(builder).

**MeshStandardNodeMaterial**: setupEnvironment(builder), setupLightingModel() → PhysicalLightingModel, setupSpecular(), setupVariants(builder).

**MeshBasicNodeMaterial**: setupEnvironment(builder), setupLightMap(builder), setupLightingModel(), setupNormal(), setupOutgoingLight().

**Line2NodeMaterial**: setup(builder) — vertex/fragment stage.

**PointsNodeMaterial**: use with THREE.Points( geometry, new THREE.PointsNodeMaterial() ); for WebGPU sprite size use Sprite + PointsNodeMaterial with positionNode.

**DotScreenNode**: setup(builder) → ShaderCallNodeInternal.

**DenoiseNode**: setup(builder).

**AttributeNode**: new AttributeNode( attributeName, nodeType ); getAttributeName(builder), setAttributeName(name).

**ReferenceNode / ReferenceBaseNode**: element(indexNode), getNodeType(builder), getValueFromReference(object), setGroup(group), setNodeType(uniformType), setup(), update(frame), updateReference(state), updateValue().

**PassNode**: getTextureNode( name ), getTexture( name ), getViewZNode( name ), getMRT(), getResolutionScale(), getPreviousTextureNode( name ), getPreviousTexture( name ), getLinearDepthNode( name ), compileAsync( renderer ).

**Texture (TSL)**: texture( value, uvNode?, levelNode?, biasNode? ), textureLoad, textureSize, textureStore, textureBarrier, textureBicubic, texture3D.

**LoopNode (TSL)**: Loop( count, ( { i } ) => { } ); Loop( { start, end, type, condition }, callback ); Loop( { start: 10 }, () => { } ) for reverse.

**ConditionalNode**: condition.select( valueIfTrue, valueIfFalse ).

**StackNode**: If( boolNode, method ), ElseIf( boolNode, method ), Else( method ), Switch( expression, method ), Case( ...params ), Default( method ).

---

## Other Addons

**RapierPhysics**
```javascript
import { RapierPhysics } from 'three/addons/physics/RapierPhysics.js';
const physics = await RapierPhysics();
```

**InteractiveGroup**
```javascript
group.listenToPointerEvents( renderer, camera );
group.listenToXRControllerEvents( controller );
scene.add( group );
group.add( mesh1, mesh2 );
```

**SelectionBox**
```javascript
import { SelectionBox } from 'three/addons/interactive/SelectionBox.js';
const selectionBox = new SelectionBox( camera, scene );
const selectedObjects = selectionBox.select( startPoint, endPoint );
```

**RectAreaLight (WebGL/WebGPU)**
```javascript
RectAreaLightUniformsLib.init(); // WebGL
THREE.RectAreaLightNode.setLTC( RectAreaLightTexturesLib.init() ); // WebGPU
const rectLight = new THREE.RectAreaLight( 0xffffff, intensity, width, height );
rectLight.position.set( 5, 5, 0 );
rectLight.lookAt( 0, 0, 0 );
scene.add( rectLight );
```

**BatchedMesh**
```javascript
const batchedMesh = new BatchedMesh( maxGeometryCount, maxVertexCount, maxIndexCount, material );
const geometryId = batchedMesh.addGeometry( geometry );
const instanceId = batchedMesh.addInstance( geometryId );
batchedMesh.setMatrixAt( instanceId, matrix );
scene.add( batchedMesh );
```

**Cache**
```javascript
THREE.Cache.enabled = true;
THREE.Cache.add( key, file );
THREE.Cache.get( key );
THREE.Cache.remove( key );
THREE.Cache.clear();
```

For more methods (e.g. Frustum, Box2, Curve, AnimationClip, SkinnedMesh, BufferGeometry attribute management), refer to the official Three.js docs; the patterns above (import path, constructor, load/parse, update/dispose) apply across addons.
