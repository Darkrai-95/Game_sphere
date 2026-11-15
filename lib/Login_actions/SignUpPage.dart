import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:gamesphere/TheProvider.dart';
import 'package:gamesphere/main.dart';
import 'package:provider/provider.dart';

class SignUpPage extends StatefulWidget{
  const SignUpPage({super.key});

  @override
  State<SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends State<SignUpPage> {
  bool _passwordvisible = false;
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _firstnameController = TextEditingController();
  final _lastnameController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose(){
    _emailController.dispose();
    _passwordController.dispose();
    _firstnameController.dispose();
    _lastnameController.dispose();
    super.dispose();
  }

  Future<void> _registerUser() async{
    if(_emailController.text.isEmpty || _passwordController.text.isEmpty || _firstnameController.text.isEmpty){
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please fill all fields",style: TextStyle(color: Colors.white)),backgroundColor: Color(0xFF1E1E24))
      );
      return;
    }

    setState(() => _isLoading = true);
    try{
      // Creates user in Firebase Auth
      UserCredential userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      User? user = userCredential.user;

      if (user != null) {
        await user.sendEmailVerification();

        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'uid': user.uid,
          'firstname': _firstnameController.text.trim(),
          'lastname' : _lastnameController.text.trim(),
          'email': _emailController.text.trim(),
          'role': 'user',
          'bio': '',
          'createAt': DateTime.now(),
          'country': 'unknown',
          'flag': '🌍',
          'phone': '',
          'institution': '',
          'dob': '(Select Date of Birth)',
          'age': 0,
        });
      }

      if (!mounted) return;
      setState(() => _isLoading = false);

      Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const VerifyEmailPage()));
    }
    on FirebaseAuthException catch (e){
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message ?? "Registration Failed", style: TextStyle(color: Colors.white)), backgroundColor: Color(0xFF1E1E24))
        );
    }
    finally{
        setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context){

    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 18, 18, 23),
      extendBodyBehindAppBar: true,
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0),
      body: Row(
        children: [
          if(!context.isMobile)Expanded(
            flex: 1,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Theme.of(context).colorScheme.primary,
                    const Color.fromARGB(255, 87, 87, 201),
                    Theme.of(context).colorScheme.primary,
                    const Color.fromARGB(255, 77, 71, 177),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Center(
              child: SingleChildScrollView(
                padding: context.isMobile? const EdgeInsets.symmetric(horizontal: 40): const EdgeInsets.symmetric(horizontal: 80),
                child: Column(
                  children: [
                    const SizedBox(height: 10),
                    Image.asset("Assets/images/icon_GameSphere.png", height: 50.0),
                    SizedBox(height: 20),
                    Text("Join GameSphere", style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white)),
                    const SizedBox(height: 40),
            
                    _buildField("First Name", _firstnameController, Icons.person_outlined),
                    const SizedBox(height: 16),
                    _buildField("Last Name", _lastnameController, Icons.person_outlined),
                    const SizedBox(height: 16),
                    _buildField("Email", _emailController, Icons.email_outlined),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _passwordController,
                      obscureText: !_passwordvisible,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: "Password",
                        hintStyle: const TextStyle(color: Colors.grey),
                        prefixIcon: Icon(Icons.lock_outline, color: Colors.grey),
                        filled: true,
                        fillColor: const Color(0xFF1E1E24),
                        suffixIcon: IconButton(
                          onPressed: () => setState(() {
                            _passwordvisible = !_passwordvisible;
                          }),
                          icon: Icon(
                            _passwordvisible? Icons.visibility: Icons.visibility_off,
                            color: Colors.grey,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Colors.white10),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFF6C63FF), width: 2),
                        ),
                      ),
                    ),
                    
                    const SizedBox(height: 32),
                    _isLoading? const CircularProgressIndicator()
                    : SizedBox(
                      width: double.infinity,
                      height: 55,
                      child: ElevatedButton(
                        onPressed: _registerUser,
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6C63FF)),
                        child: const Text(
                          "CREATE ACCOUNT", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                ),
              ),
            ),
          ),
          if(!context.isMobile)Expanded(
            flex: 1,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Theme.of(context).colorScheme.primary,
                    const Color.fromARGB(255, 67, 56, 139),
                    Theme.of(context).colorScheme.primary,
                    const Color.fromARGB(255, 57, 40, 117),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildField(String hint, TextEditingController controller, IconData icon, {bool isPass = false}){
    return TextField(
      controller: controller,
      obscureText: isPass,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.grey),
        prefixIcon: Icon(icon, color: Colors.grey),
        filled: true,
        fillColor: const Color(0xFF1E1E24),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.white10),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF6C63FF), width: 2),
        ),
      ),
    );
  }
}


class VerifyEmailPage extends StatefulWidget {
  const VerifyEmailPage({super.key});

  @override
  State<VerifyEmailPage> createState() => _VerifyEmailPageState();
}

class _VerifyEmailPageState extends State<VerifyEmailPage>{
  bool isEmailVerified = false;
  Timer? timer;

  @override
  void initState(){
    super.initState();

    isEmailVerified = FirebaseAuth.instance.currentUser!.emailVerified;

    if(!isEmailVerified){
      timer = Timer.periodic(const Duration(seconds: 3), (_) => checkEmailVerified());
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future checkEmailVerified() async {
    await FirebaseAuth.instance.currentUser?.reload();
    final user = FirebaseAuth.instance.currentUser;

    if(user != null && user.emailVerified){
      timer?.cancel();
      if(!mounted) return;
      
      setState(() {
        isEmailVerified = true;
        Provider.of<UserProvider>(context, listen: false).fetchUserData(user.uid);
        Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (context) => GameSphereHome()),
          (route) => false,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Verify Email')),
    body: Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.email_outlined, size: 100, color: Colors.blueAccent),
            const SizedBox(height: 24),
            const Text(
              'A verification email has been sent!',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            const Text(
              'Please check your inbox and click the link to continue.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => FirebaseAuth.instance.currentUser?.sendEmailVerification(),
              icon: const Icon(Icons.refresh),
              label: const Text('Resend Email'),
            ),
            TextButton(
              onPressed: () async{
                timer?.cancel();
                await FirebaseAuth.instance.signOut();
              },
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    ),
  );
}